package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"golang.org/x/term"
)

// TerminalDimensions holds exact terminal measurements
type TerminalDimensions struct {
	CellHeight   int
	CellWidth    int
	WindowWidth  int
	WindowHeight int
}

// detectTerminalDimensions queries the terminal for exact pixel dimensions.
// The goroutine reading stdin will leak if the timeout fires, but this only
// runs once at startup and the blocked goroutine is cleaned up on process exit.
func detectTerminalDimensions() TerminalDimensions {
	dims := TerminalDimensions{
		CellHeight:   20,   // fallback
		CellWidth:    10,   // fallback
		WindowWidth:  1920, // fallback
		WindowHeight: 1080, // fallback
	}

	oldState, err := term.MakeRaw(int(os.Stdin.Fd()))
	if err != nil {
		return dims
	}
	defer term.Restore(int(os.Stdin.Fd()), oldState)

	// Query for cell size (CSI 16 t) and window size (CSI 14 t)
	fmt.Print("\033[16t\033[14t")

	response := make([]byte, 128)
	done := make(chan int)

	go func() {
		n, _ := os.Stdin.Read(response)
		done <- n
	}()

	select {
	case n := <-done:
		resp := string(response[:n])

		// Parse cell size: ESC [ 6 ; height ; width t
		if idx := strings.Index(resp, "\033[6;"); idx >= 0 {
			parts := strings.Split(resp[idx+4:], ";")
			if len(parts) >= 2 {
				if h, err := strconv.Atoi(parts[0]); err == nil && h > 0 {
					dims.CellHeight = h
				}
				endIdx := strings.IndexByte(parts[1], 't')
				if endIdx > 0 {
					if w, err := strconv.Atoi(parts[1][:endIdx]); err == nil && w > 0 {
						dims.CellWidth = w
					}
				}
			}
		}

		// Parse window size: ESC [ 4 ; height ; width t
		if idx := strings.Index(resp, "\033[4;"); idx >= 0 {
			parts := strings.Split(resp[idx+4:], ";")
			if len(parts) >= 2 {
				if h, err := strconv.Atoi(parts[0]); err == nil && h > 0 {
					dims.WindowHeight = h
				}
				endIdx := strings.IndexByte(parts[1], 't')
				if endIdx > 0 {
					if w, err := strconv.Atoi(parts[1][:endIdx]); err == nil && w > 0 {
						dims.WindowWidth = w
					}
				}
			}
		}
	case <-time.After(100 * time.Millisecond):
		// Timeout - use fallbacks
	}

	return dims
}
