package main

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/google/generative-ai-go/genai"
	"google.golang.org/api/option"
)

type RunRequest struct {
	Code string `json:"code"`
}

type RunResponse struct {
	Output string `json:"output,omitempty"`
	Error  string `json:"error,omitempty"`
	Gemini string `json:"gemini,omitempty"` // phản hồi từ Gemini nếu có lỗi
}

var geminiClient *genai.Client
var geminiModel *genai.GenerativeModel

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
	geminiClient = client
	geminiModel = client.GenerativeModel("gemini-flash-lite-latest")
}

func main() {
	initGemini()

	r := gin.Default()
	r.Use(cors.Default()) // Cho phép mọi origin (có thể giới hạn sau)

	r.POST("/run", handleRun)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	// Thay vì r.Run(":" + port)
        r.Run("0.0.0.0:" + port)   // Lắng nghe trên tất cả địa chỉ
}

func handleRun(c *gin.Context) {
	var req RunRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	// Tạo thư mục tạm
	tmpDir, err := os.MkdirTemp("", "gobuild-*")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create temp dir"})
		return
	}
	defer os.RemoveAll(tmpDir)

	// Ghi file main.go
	mainGoPath := filepath.Join(tmpDir, "main.go")
	if err := os.WriteFile(mainGoPath, []byte(req.Code), 0644); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to write code"})
		return
	}

	// Biên dịch
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	buildCmd := exec.CommandContext(ctx, "go", "build", "-o", filepath.Join(tmpDir, "app"), mainGoPath)
	buildCmd.Dir = tmpDir
	var buildStderr bytes.Buffer
	buildCmd.Stderr = &buildStderr
	if err := buildCmd.Run(); err != nil {
		// Lỗi biên dịch
		buildErr := buildStderr.String()
		geminiResp := callGemini(buildErr, req.Code)
		c.JSON(http.StatusBadRequest, RunResponse{
			Error:  buildErr,
			Gemini: geminiResp,
		})
		return
	}

	// Thực thi
	runCmd := exec.CommandContext(ctx, filepath.Join(tmpDir, "app"))
	var runStdout, runStderr bytes.Buffer
	runCmd.Stdout = &runStdout
	runCmd.Stderr = &runStderr
	if err := runCmd.Run(); err != nil {
		// Lỗi runtime
		runErr := runStderr.String()
		if runErr == "" {
			runErr = err.Error()
		}
		geminiResp := callGemini(runErr, req.Code)
		c.JSON(http.StatusBadRequest, RunResponse{
			Error:  runErr,
			Gemini: geminiResp,
		})
		return
	}

	// Thành công
	output := runStdout.String()
	c.JSON(http.StatusOK, RunResponse{
		Output: output,
	})
}

// callGemini gửi lỗi và code đến Gemini để nhận phân tích
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

	// Lấy text từ phần đầu tiên
	part := resp.Candidates[0].Content.Parts[0]
	if text, ok := part.(genai.Text); ok {
		return string(text)
	}
	return "Phản hồi từ Gemini không hợp lệ."
}
