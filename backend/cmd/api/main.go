package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"kula.local/backend/internal/catalog"
	"kula.local/backend/internal/discovery"
)

func main() {
	if err := run(); err != nil {
		slog.Error("API stopped", "error", err)
		os.Exit(1)
	}
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	key := strings.TrimSpace(os.Getenv("GOOGLE_MAPS_API_KEY"))
	if path := os.Getenv("GOOGLE_MAPS_API_KEY_FILE"); key == "" && path != "" {
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read Places key file: %w", err)
		}
		key = strings.TrimSpace(string(data))
	}
	mux := http.NewServeMux()
	mux.Handle("/v1/discovery/restaurants", discovery.NewHandler(key))
	mux.Handle("/", catalog.Handler())

	server := &http.Server{
		Addr:              "127.0.0.1:8087",
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}
	result := make(chan error, 1)
	go func() { result <- server.ListenAndServe() }()
	slog.Info("starting local demo API", "address", server.Addr)

	select {
	case err := <-result:
		return err
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			return err
		}
		if err := <-result; !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	}
}
