package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/google/generative-ai-go/genai"
	"google.golang.org/api/option"
)

// ---------------------------------------------------------------------------
// Request / Response types
// ---------------------------------------------------------------------------

type RunRequest struct {
	Code  string `json:"code"`
	GoMod string `json:"goMod,omitempty"`
}

type RunResponse struct {
	Output string `json:"output,omitempty"`
	Error  string `json:"error,omitempty"`
	Gemini string `json:"gemini,omitempty"`
}

type GenerateRequest struct {
	Prompt string `json:"prompt"`
}

type GenerateResponse struct {
	Code  string `json:"code,omitempty"`
	GoMod string `json:"goMod,omitempty"`
	Error string `json:"error,omitempty"`
}

type FormatRequest struct {
	Code string `json:"code"`
}

type FormatResponse struct {
	Code  string `json:"code,omitempty"`
	Error string `json:"error,omitempty"`
}

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------

var geminiModel *genai.GenerativeModel

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

func initGemini() {
	apiKey := os.Getenv("GEMINI_API_KEY")
	if apiKey == "" {
		log.Fatal("GEMINI_API_KEY not set")
	}
	ctx := context.Background()
	client, err := genai.NewClient(ctx, option.WithAPIKey(apiKey))
	if err != nil {
		log.Fatalf("Failed to create Gemini client: %v", err)
	}
	geminiModel = client.GenerativeModel("gemini-flash-lite-latest")
}

func main() {
	initGemini()

	r := gin.Default()
	r.Use(cors.Default())

	r.POST("/run", handleRun)
	r.POST("/generate", handleGenerate)
	r.POST("/format", handleFormat)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("🚀 Backend Go Droid lắng nghe tại :%s", port)
	if err := r.Run("0.0.0.0:" + port); err != nil {
		log.Fatal(err)
	}
}

// ---------------------------------------------------------------------------
// /run — build & execute user code
// ---------------------------------------------------------------------------

func handleRun(c *gin.Context) {
	var req RunRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	hasGoMod := strings.TrimSpace(req.GoMod) != ""
	log.Printf("📥 /run code=%d bytes, goMod=%v", len(req.Code), hasGoMod)

	// 1) Workspace tạm
	tmpDir, err := os.MkdirTemp("", "godroid-*")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create temp dir"})
		return
	}
	defer os.RemoveAll(tmpDir)

	// 2) Ghi main.go
	mainGoPath := filepath.Join(tmpDir, "main.go")
	if err := os.WriteFile(mainGoPath, []byte(req.Code), 0o644); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to write code"})
		return
	}

	// 3) Ghi go.mod
	goModContent := req.GoMod
	if !hasGoMod {
		goModContent = "module godroid/main\n\ngo 1.21\n"
		log.Println("⚠️  Không có go.mod từ client → dùng skeleton")
	}
	goModPath := filepath.Join(tmpDir, "go.mod")
	if err := os.WriteFile(goModPath, []byte(goModContent), 0o644); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to write go.mod"})
		return
	}
	log.Printf("📝 go.mod:\n%s", goModContent)

	// Env chung cho mọi lệnh Go trong workspace.
	gomodCache := os.Getenv("GOMODCACHE")
	if gomodCache == "" {
		gomodCache = filepath.Join(os.TempDir(), "godroid-gomodcache")
	}
	gocache := os.Getenv("GOCACHE")
	if gocache == "" {
		gocache = filepath.Join(os.TempDir(), "godroid-gocache")
	}
	baseEnv := []string{
		"CGO_ENABLED=0",
		"GOFLAGS=-mod=mod",
		"GOPROXY=https://proxy.golang.org,direct",
		"GOSUMDB=sum.golang.org",
		"GOMODCACHE=" + gomodCache,
		"GOCACHE=" + gocache,
	}

	// 4) `go mod tidy` — resolve dependency, tạo go.sum.
	tidyCtx, tidyCancel := context.WithTimeout(c.Request.Context(), 90*time.Second)
	defer tidyCancel()

	log.Println("⚙️  Chạy `go mod tidy`...")
	tidyStart := time.Now()
	tidyOut, tidyErr := runCmd(tidyCtx, tmpDir, baseEnv, "go", "mod", "tidy")
	log.Printf("   → err=%v, %v", tidyErr, time.Since(tidyStart))

	if tidyErr != nil {
		errMsg := tidyOut
		if strings.TrimSpace(errMsg) == "" {
			errMsg = tidyErr.Error()
		}
		full := "Lỗi khi chạy `go mod tidy`:\n" + errMsg
		log.Printf("❌ %s", full)
		geminiResp := callGemini(full, req.Code)
		c.JSON(http.StatusBadRequest, RunResponse{Error: full, Gemini: geminiResp})
		return
	}

	// 5) `go build .`
	buildCtx, buildCancel := context.WithTimeout(c.Request.Context(), 60*time.Second)
	defer buildCancel()

	appPath := filepath.Join(tmpDir, "app")
	log.Println("🔨 Chạy `go build`...")
	buildOut, buildErr := runCmd(buildCtx, tmpDir, baseEnv,
		"go", "build", "-o", appPath, ".")
	if buildErr != nil {
		errMsg := buildOut
		if strings.TrimSpace(errMsg) == "" {
			errMsg = buildErr.Error()
		}
		log.Printf("❌ build: %s", errMsg)
		geminiResp := callGemini(errMsg, req.Code)
		c.JSON(http.StatusBadRequest, RunResponse{Error: errMsg, Gemini: geminiResp})
		return
	}

	// 6) Chạy binary, timeout riêng vì code có thể loop vô hạn.
	runCtx, runCancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer runCancel()

	log.Println("▶️  Chạy app...")
	runOut, runErr := runCmd(runCtx, tmpDir, []string{"CGO_ENABLED=0"}, appPath)
	if runErr != nil {
		errMsg := runOut
		if errors.Is(runCtx.Err(), context.DeadlineExceeded) {
			errMsg = "Chương trình chạy quá thời gian cho phép (15s) — có thể bị treo vô hạn."
		} else if strings.TrimSpace(errMsg) == "" {
			errMsg = runErr.Error()
		}
		log.Printf("❌ run: %s", errMsg)
		geminiResp := callGemini(errMsg, req.Code)
		c.JSON(http.StatusBadRequest, RunResponse{Error: errMsg, Gemini: geminiResp})
		return
	}

	log.Printf("✅ Thành công (%d bytes output)", len(runOut))
	c.JSON(http.StatusOK, RunResponse{Output: runOut})
}

// ---------------------------------------------------------------------------
// /generate — Gemini code generation
// ---------------------------------------------------------------------------

func handleGenerate(c *gin.Context) {
	var req GenerateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, GenerateResponse{Error: "invalid request"})
		return
	}

	if geminiModel == nil {
		c.JSON(http.StatusInternalServerError, GenerateResponse{Error: "Gemini not ready"})
		return
	}

	prompt := fmt.Sprintf(`
Bạn là một lập trình viên Go chuyên nghiệp. Hãy viết code Go hoàn chỉnh để thực hiện yêu cầu sau:

%s

Yêu cầu output:
- Chỉ trả về code, KHÔNG thêm giải thích ngoài.
- Đặt code Go giữa <CODE>...</CODE>.
- NẾU code cần import package ngoài stdlib, đặt nội dung go.mod giữa <GOMOD>...</GOMOD>. Ngược lại bỏ qua thẻ GOMOD.
- Code phải có package main và hàm main.

Ví dụ khi cần go.mod:
<CODE>
package main

import (
    "fmt"
    "github.com/google/uuid"
)

func main() {
    fmt.Println(uuid.New().String())
}
</CODE>
<GOMOD>
module godroid/main

go 1.21

require github.com/google/uuid latest
</GOMOD>
`, req.Prompt)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 30*time.Second)
	defer cancel()

	resp, err := geminiModel.GenerateContent(ctx, genai.Text(prompt))
	if err != nil {
		log.Printf("Gemini generate error: %v", err)
		c.JSON(http.StatusInternalServerError, GenerateResponse{Error: "Failed to generate code"})
		return
	}

	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		c.JSON(http.StatusInternalServerError, GenerateResponse{Error: "No response from Gemini"})
		return
	}

	part := resp.Candidates[0].Content.Parts[0]
	text, ok := part.(genai.Text)
	if !ok {
		c.JSON(http.StatusInternalServerError, GenerateResponse{Error: "Invalid response from Gemini"})
		return
	}

	code, goMod := parseGeneratedCode(string(text))
	c.JSON(http.StatusOK, GenerateResponse{Code: code, GoMod: goMod})
}

// parseGeneratedCode tách code Go và go.mod từ output Gemini.
// Ưu tiên thẻ <CODE>/<GOMOD>, fallback sang markdown fence.
func parseGeneratedCode(raw string) (code string, goMod string) {
	if c := extractBetween(raw, "<CODE>", "</CODE>"); c != "" {
		code = strings.TrimSpace(c)
		goMod = strings.TrimSpace(extractBetween(raw, "<GOMOD>", "</GOMOD>"))
		if code != "" {
			return code, goMod
		}
	}

	// Fallback: markdown fence ```go ... ``` và ```go.mod ... ```
	for _, f := range []string{"```go", "```golang"} {
		if c := extractFence(raw, f); c != "" {
			code = c
			break
		}
	}
	if code == "" {
		if c := extractFence(raw, "```"); c != "" {
			code = c
		}
	}
	for _, f := range []string{"```go.mod", "```gomod", "```mod"} {
		if g := extractFence(raw, f); g != "" {
			goMod = g
			break
		}
	}
	if code == "" {
		code = strings.TrimSpace(raw)
	}
	return code, goMod
}

func extractBetween(s, open, closeTag string) string {
	i := strings.Index(s, open)
	if i < 0 {
		return ""
	}
	rest := s[i+len(open):]
	j := strings.Index(rest, closeTag)
	if j < 0 {
		return ""
	}
	return rest[:j]
}

func extractFence(s, fence string) string {
	i := strings.Index(s, fence)
	if i < 0 {
		return ""
	}
	rest := s[i+len(fence):]
	rest = strings.TrimPrefix(rest, "\r\n")
	rest = strings.TrimPrefix(rest, "\n")
	j := strings.Index(rest, "```")
	if j < 0 {
		return ""
	}
	return strings.TrimSpace(rest[:j])
}

// ---------------------------------------------------------------------------
// /format — gofmt
// ---------------------------------------------------------------------------

func handleFormat(c *gin.Context) {
	var req FormatRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, FormatResponse{Error: "invalid request"})
		return
	}

	if strings.TrimSpace(req.Code) == "" {
		c.JSON(http.StatusOK, FormatResponse{Code: ""})
		return
	}

	cmd := exec.Command("gofmt")
	cmd.Stdin = strings.NewReader(req.Code)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = err.Error()
		}
		log.Printf("❌ gofmt: %s", msg)
		c.JSON(http.StatusBadRequest, FormatResponse{Error: msg})
		return
	}

	c.JSON(http.StatusOK, FormatResponse{Code: stdout.String()})
}

// ---------------------------------------------------------------------------
// Gemini helper cho lỗi runtime
// ---------------------------------------------------------------------------

func callGemini(errorMsg, code string) string {
	if geminiModel == nil {
		return "Gemini client not initialized"
	}

	prompt := fmt.Sprintf(`
Bạn là trợ lý lập trình Go. Người dùng đã gặp lỗi sau khi biên dịch/chạy code Go:

Code:
%s

Lỗi:
%s

Hãy giải thích nguyên nhân và đề xuất cách sửa lỗi một cách ngắn gọn, dễ hiểu (bằng tiếng Việt).
`, code, errorMsg)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	resp, err := geminiModel.GenerateContent(ctx, genai.Text(prompt))
	if err != nil {
		log.Printf("Gemini error: %v", err)
		return "Không thể nhận phản hồi từ Gemini, vui lòng thử lại."
	}

	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return "Gemini không đưa ra phản hồi."
	}

	part := resp.Candidates[0].Content.Parts[0]
	if text, ok := part.(genai.Text); ok {
		return string(text)
	}
	return "Phản hồi từ Gemini không hợp lệ."
}

// ---------------------------------------------------------------------------
// Command runner — CHỈ 1 hàm duy nhất.
// ---------------------------------------------------------------------------

// runCmd chạy `name args...` trong `dir` với env bổ sung.
// Trả về (stdout+stderr gộp, error). Error luôn chứa output khi có thể
// để client hiển thị dễ debug.
func runCmd(
	ctx context.Context,
	dir string,
	extraEnv []string,
	name string,
	args ...string,
) (string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), extraEnv...)

	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf

	runErr := cmd.Run()
	out := buf.String()

	if ctx.Err() == context.DeadlineExceeded {
		return out, fmt.Errorf("timeout: %w", ctx.Err())
	}

	if runErr != nil {
		if strings.TrimSpace(out) == "" {
			return out, runErr
		}
		return out, errors.New(out)
	}
	return out, nil
}