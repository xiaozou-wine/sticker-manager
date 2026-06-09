package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"sticker-server/handler"
	"sticker-server/service"
	"sticker-server/store"
)

func main() {
	port := flag.Int("port", 28749, "server port")
	dbPath := flag.String("db", "./data/stickers.db", "SQLite database path")
	staticDir := flag.String("static", "./static", "static files directory")
	baseURL := flag.String("base-url", "", "base URL for file links (e.g. http://your-server:28749)")
	corsOrigin := flag.String("cors-origin", "*", "allowed CORS origin (use specific domain in production)")
	flag.Parse()

	if *baseURL == "" {
		*baseURL = fmt.Sprintf("http://localhost:%d", *port)
	}

	// Ensure static dir exists
	if err := os.MkdirAll(*staticDir, 0755); err != nil {
		log.Fatalf("Failed to create static dir: %v", err)
	}

	// Initialize database
	db, err := store.New(*dbPath)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer db.Close()

	// Initialize services
	packSvc := service.NewPackService(db, *baseURL)

	// Initialize handlers
	packHandler := handler.NewPackHandler(packSvc, *staticDir)

	// Setup router
	r := gin.Default()

	// #3 CORS: configurable origin
	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", *corsOrigin)
		c.Header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	// Limit upload size to 50MB
	r.MaxMultipartMemory = 50 << 20

	// API routes
	api := r.Group("/api")
	{
		api.POST("/packs", packHandler.CreatePack)
		api.GET("/packs/:code", packHandler.GetPack)
		api.GET("/packs/:code/stickers", packHandler.GetPackStickers)
		api.GET("/stickers/:id/file", packHandler.GetStickerFile)
		api.DELETE("/packs/:code", packHandler.DeletePack)
	}

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	addr := fmt.Sprintf(":%d", *port)
	log.Printf("Sticker server starting on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
