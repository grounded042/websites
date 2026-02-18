package main

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"gopkg.in/gographics/imagick.v3/imagick"
)

const (
	aspectRatio      = 3.0  // 3:1 ratio for cover photos
	scrollStep       = 10   // pixels per arrow key press
	scrollStepLarge  = 50   // pixels per shift+arrow key press
	darkenBrightness = 40   // ModulateImage brightness percentage
	previewMarginPx  = 20   // pixel margin subtracted from window width
	uiReservedRows   = 5    // header + stats + footer + 1 bar row above + 1 below
	kittyChunkSize   = 4096 // base64 bytes per Kitty protocol chunk
	kittyBaseID      = 10   // strip image IDs: kittyBaseID + row
	edgePad          = 2    // minimum left/right padding from terminal edges
	barPxTotal       = 20   // pixel width of bar area prepended to each image strip
	barLineCenter    = 14   // X pixel position of bar line center
	barCropRadius    = 1    // bar line half-width in crop region (3px total)
	barTickStart     = 4    // leftmost X pixel of tick marks
	barTickThick     = 2    // tick mark thickness in pixels

	colorTitle   = "12"  // blue
	colorInfo    = "247" // light gray
	colorHelp    = "6"   // cyan
	colorSuccess = "10"  // green
	colorError   = "9"   // red
	colorDim     = "240" // dim gray for timing/cache/labels
	colorMarker  = "4"   // crop boundary markers (blue, text labels)
)

type model struct {
	sourcePath       string
	outputPath       string
	sourceFileSize   int64
	sourceWidth      uint
	sourceHeight     uint
	sourceDepth      uint
	cropWidth        uint
	cropHeight       uint
	yOffset          int
	maxYOffset       int
	strips           []string // per-row Kitty a=T commands
	previewRowCount  int
	previewWidthCols int // bar + image columns
	imageCols        int // image-only columns
	err              error
	saved            bool
	terminalWidth    int
	terminalHeight   int
	termDims         TerminalDimensions
	lastRenderTime   time.Duration
	cacheBytes       int64

	// Full-resolution source (loaded once, never reloaded)
	sourceWand *imagick.MagickWand
	// Cached preview-resolution images (rebuilt on resize, not from disk)
	darkPreview   *imagick.MagickWand
	brightPreview *imagick.MagickWand
	scaleRatio    float64
	needsDelete   bool // Delete old Kitty images on next render (resize only)
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "Usage: cover-crop <source_image> [output_path]")
		fmt.Fprintln(os.Stderr, "Example: cover-crop jonhikes/content/posts/my-trip/images/1.HEIC")
		os.Exit(1)
	}

	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	imagick.Initialize()
	defer imagick.Terminate()

	sourcePath := os.Args[1]
	outputPath := ""
	if len(os.Args) > 2 {
		outputPath = os.Args[2]
	} else {
		outputPath = filepath.Join(filepath.Dir(sourcePath), "cover.HEIC")
	}

	fi, err := os.Stat(sourcePath)
	if err != nil {
		return fmt.Errorf("stat source: %w", err)
	}

	sourceWand := imagick.NewMagickWand()
	defer sourceWand.Destroy()

	if err := sourceWand.ReadImage(sourcePath); err != nil {
		return fmt.Errorf("reading image: %w", err)
	}
	width := sourceWand.GetImageWidth()
	height := sourceWand.GetImageHeight()
	depth := sourceWand.GetImageDepth()

	cropWidth, cropHeight := calculateCropDimensions(width, height)
	if cropWidth == 0 || cropHeight == 0 {
		return fmt.Errorf("image too small for %v:1 crop", aspectRatio)
	}

	maxYOffset := int(height - cropHeight)

	m := model{
		sourcePath:     sourcePath,
		outputPath:     outputPath,
		sourceFileSize: fi.Size(),
		sourceWidth:    width,
		sourceHeight:   height,
		sourceDepth:    depth,
		cropWidth:      cropWidth,
		cropHeight:     cropHeight,
		yOffset:        maxYOffset / 2,
		maxYOffset:     maxYOffset,
		termDims:       detectTerminalDimensions(),
		sourceWand:     sourceWand,
	}

	p := tea.NewProgram(m, tea.WithAltScreen())
	_, err = p.Run()
	return err
}

func calculateCropDimensions(sourceWidth, sourceHeight uint) (uint, uint) {
	cropWidth := sourceWidth
	cropHeight := uint(float64(cropWidth) / aspectRatio)

	if cropHeight > sourceHeight {
		cropHeight = sourceHeight
		cropWidth = uint(float64(cropHeight) * aspectRatio)
	}

	return cropWidth, cropHeight
}

// barCols returns the number of terminal columns for the text bar area.
func (m model) barCols() int {
	return len(strconv.Itoa(int(m.sourceHeight))) + 1 // label + space (bar is pixel-rendered in strip)
}

func (m model) Init() tea.Cmd {
	return nil
}

// adjustOffset clamps yOffset after applying delta. Returns true if offset changed.
func (m *model) adjustOffset(delta int) bool {
	old := m.yOffset
	m.yOffset = max(0, min(m.yOffset+delta, m.maxYOffset))
	return m.yOffset != old
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	m.needsDelete = false

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.terminalWidth = msg.Width
		m.terminalHeight = msg.Height
		m.needsDelete = true
		if err := m.buildPreviewCache(); err != nil {
			m.err = err
			return m, tea.Quit
		}
		strips, dur, err := m.generatePreview()
		if err != nil {
			m.err = err
			return m, tea.Quit
		}
		m.strips = strips
		m.lastRenderTime = dur
		return m, nil

	case tea.KeyMsg:
		var changed bool
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "up", "k":
			changed = m.adjustOffset(-scrollStep)
		case "down", "j":
			changed = m.adjustOffset(scrollStep)
		case "shift+up", "K":
			changed = m.adjustOffset(-scrollStepLarge)
		case "shift+down", "J":
			changed = m.adjustOffset(scrollStepLarge)
		case "enter":
			if err := m.saveCrop(); err != nil {
				m.err = err
			} else {
				m.saved = true
			}
			return m, tea.Quit
		}
		if changed {
			strips, dur, err := m.generatePreview()
			if err != nil {
				m.err = err
				return m, tea.Quit
			}
			m.strips = strips
			m.lastRenderTime = dur
		}
	}

	return m, nil
}

func (m model) View() string {
	if m.saved {
		style := lipgloss.NewStyle().Foreground(lipgloss.Color(colorSuccess)).Bold(true)
		return style.Render(fmt.Sprintf("✓ Cover photo saved to: %s\n", m.outputPath))
	}

	if m.err != nil {
		style := lipgloss.NewStyle().Foreground(lipgloss.Color(colorError)).Bold(true)
		return style.Render(fmt.Sprintf("Error: %v\n", m.err))
	}

	if len(m.strips) == 0 {
		return "Loading..."
	}

	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color(colorTitle))
	infoStyle := lipgloss.NewStyle().Foreground(lipgloss.Color(colorInfo))
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color(colorDim))
	helpStyle := lipgloss.NewStyle().Foreground(lipgloss.Color(colorHelp))
	markerStyle := lipgloss.NewStyle().Foreground(lipgloss.Color(colorMarker))

	// Estimate builder capacity from strip data
	totalStripLen := 0
	for _, s := range m.strips {
		totalStripLen += len(s)
	}
	var b strings.Builder
	b.Grow(totalStripLen + 4096)

	if m.needsDelete {
		b.WriteString("\033_Ga=d,d=a\033\\") // delete all images (safe in alt-screen)
	}

	// Header: title centered, render time right-aligned
	edge := strings.Repeat(" ", edgePad)
	title := titleStyle.Render("Cover Photo Cropper")
	timing := dimStyle.Render(fmt.Sprintf("%dms", m.lastRenderTime.Milliseconds()))
	titleW := lipgloss.Width(title)
	timingW := lipgloss.Width(timing)
	usable := m.terminalWidth - 2*edgePad
	centerPos := max(0, (usable-titleW)/2)
	rightPos := max(centerPos+titleW+1, usable-timingW)
	b.WriteString(edge)
	b.WriteString(strings.Repeat(" ", centerPos))
	b.WriteString(title)
	b.WriteString(strings.Repeat(" ", max(1, rightPos-centerPos-titleW)))
	b.WriteString(timing)
	b.WriteByte('\n')

	// Stats: file info left, crop coordinates right
	megapixels := float64(m.sourceWidth) * float64(m.sourceHeight) / 1e6
	statsLeft := infoStyle.Render(fmt.Sprintf("%d×%d · %.1f MP · %s · %d-bit",
		m.sourceWidth, m.sourceHeight, megapixels, formatBytes(m.sourceFileSize), m.sourceDepth))
	cropEndY := m.yOffset + int(m.cropHeight)
	statsRight := infoStyle.Render(fmt.Sprintf("crop (0,%d)→(%d,%d)",
		m.yOffset, m.cropWidth, cropEndY))
	gap := max(1, m.terminalWidth-2*edgePad-lipgloss.Width(statsLeft)-lipgloss.Width(statsRight))
	b.WriteString(edge)
	b.WriteString(statsLeft)
	b.WriteString(strings.Repeat(" ", gap))
	b.WriteString(statsRight)
	b.WriteByte('\n')

	// Layout
	leftPad := max(edgePad, (m.terminalWidth-m.previewWidthCols)/2)
	labelWidth := m.barCols() - 1 // digits only (barCols = digits + space)

	// Content rows between stats and footer
	totalContentRows := m.terminalHeight - 3
	totalPadding := max(2, totalContentRows-m.previewRowCount)
	topRows := totalPadding / 2
	bottomRows := totalPadding - topRows

	// Determine which image rows get labels
	cellH := m.termDims.CellHeight
	cropStartRow := int(float64(m.yOffset)*m.scaleRatio) / cellH
	cropEndRow := int(float64(cropEndY)*m.scaleRatio) / cellH
	lastRow := m.previewRowCount - 1

	type rowLabel struct {
		text     string
		isMarker bool
	}
	labels := map[int]rowLabel{}
	labels[0] = rowLabel{"0", false}
	if lastRow != 0 {
		labels[lastRow] = rowLabel{strconv.Itoa(int(m.sourceHeight)), false}
	}
	labels[cropStartRow] = rowLabel{strconv.Itoa(m.yOffset), true}
	if cropEndRow != cropStartRow {
		labels[cropEndRow] = rowLabel{strconv.Itoa(cropEndY), true}
	}

	// Top padding
	for range topRows {
		b.WriteByte('\n')
	}

	// Image rows: text label + Kitty strip (bar is pixel-rendered in the strip)
	for row := range m.previewRowCount {
		b.WriteString(strings.Repeat(" ", leftPad))

		if lbl, ok := labels[row]; ok {
			pad := labelWidth - len(lbl.text)
			if pad > 0 {
				b.WriteString(strings.Repeat(" ", pad))
			}
			if lbl.isMarker {
				b.WriteString(markerStyle.Render(lbl.text))
			} else {
				b.WriteString(dimStyle.Render(lbl.text))
			}
		} else {
			b.WriteString(strings.Repeat(" ", labelWidth))
		}

		b.WriteByte(' ')

		if row < len(m.strips) {
			b.WriteString(m.strips[row])
		}
		b.WriteByte('\n')
	}

	// Bottom padding
	for range bottomRows {
		b.WriteByte('\n')
	}

	// Footer: help left, cache size right
	footerLeft := helpStyle.Render("↑/k ↓/j: 10px   K/J: 50px   Enter: save   q: quit")
	footerRight := dimStyle.Render(fmt.Sprintf("cache: %s", formatBytes(m.cacheBytes)))
	gap = max(1, m.terminalWidth-2*edgePad-lipgloss.Width(footerLeft)-lipgloss.Width(footerRight))
	b.WriteString(edge)
	b.WriteString(footerLeft)
	b.WriteString(strings.Repeat(" ", gap))
	b.WriteString(footerRight)

	return b.String()
}

// formatBytes formats a byte count as a human-readable string.
func formatBytes(b int64) string {
	switch {
	case b >= 1<<20:
		return fmt.Sprintf("%.1f MB", float64(b)/float64(1<<20))
	case b >= 1<<10:
		return fmt.Sprintf("%.1f KB", float64(b)/float64(1<<10))
	default:
		return fmt.Sprintf("%d B", b)
	}
}

// buildPreviewCache resizes the source to preview dimensions and caches both
// dark and bright versions. Called on first render and on terminal resize.
//
// Uses a pointer receiver to mutate the model copy returned by Update.
// This works correctly with Bubble Tea's value-receiver pattern because
// Update takes the address of its copy, mutates it here, then returns it.
func (m *model) buildPreviewCache() error {
	if m.darkPreview != nil {
		m.darkPreview.Destroy()
		m.darkPreview = nil
	}
	if m.brightPreview != nil {
		m.brightPreview.Destroy()
		m.brightPreview = nil
	}

	maxPreviewRows := max(5, m.terminalHeight-uiReservedRows)

	// Reserve space for the text labels and pixel bar
	textPx := m.barCols() * m.termDims.CellWidth
	maxPreviewWidth := uint(m.termDims.WindowWidth - previewMarginPx - textPx - barPxTotal)

	previewWidth := m.sourceWidth
	previewHeightPx := m.sourceHeight

	m.scaleRatio = 1.0
	if previewWidth > maxPreviewWidth {
		m.scaleRatio = float64(maxPreviewWidth) / float64(previewWidth)
		previewWidth = maxPreviewWidth
		previewHeightPx = uint(float64(previewHeightPx) * m.scaleRatio)
	}

	maxPreviewHeightPx := uint(maxPreviewRows * m.termDims.CellHeight)
	if previewHeightPx > maxPreviewHeightPx {
		ratio := float64(maxPreviewHeightPx) / float64(previewHeightPx)
		m.scaleRatio *= ratio
		previewHeightPx = maxPreviewHeightPx
		previewWidth = uint(float64(previewWidth) * ratio)
	}

	m.previewRowCount = (int(previewHeightPx) + m.termDims.CellHeight - 1) / m.termDims.CellHeight
	m.imageCols = (barPxTotal + int(previewWidth) + m.termDims.CellWidth - 1) / m.termDims.CellWidth
	m.previewWidthCols = m.imageCols + m.barCols()

	bright := m.sourceWand.Clone()
	if err := bright.ResizeImage(previewWidth, previewHeightPx, imagick.FILTER_LANCZOS); err != nil {
		bright.Destroy()
		return fmt.Errorf("resizing preview: %w", err)
	}
	m.brightPreview = bright

	dark := bright.Clone()
	if err := dark.ModulateImage(darkenBrightness, 100, 100); err != nil {
		dark.Destroy()
		return fmt.Errorf("darkening preview: %w", err)
	}
	m.darkPreview = dark

	pixelCount := int64(previewWidth) * int64(previewHeightPx)
	m.cacheBytes = pixelCount * 4 * 2

	return nil
}

// generatePreview composites the bright crop region onto the dark base image,
// then splits it into per-row Kitty strips. Each strip uses a=T with a unique
// image ID so that text labels can be rendered on the same terminal row.
//
// Uses a pointer receiver for the same reason as buildPreviewCache.
func (m *model) generatePreview() ([]string, time.Duration, error) {
	start := time.Now()

	if m.darkPreview == nil {
		return nil, 0, fmt.Errorf("no preview cache")
	}

	composite := m.darkPreview.Clone()
	defer composite.Destroy()

	cropWand := m.brightPreview.Clone()
	defer cropWand.Destroy()

	cropPreviewWidth := uint(float64(m.cropWidth) * m.scaleRatio)
	cropPreviewHeight := uint(float64(m.cropHeight) * m.scaleRatio)
	cropPreviewY := int(float64(m.yOffset) * m.scaleRatio)

	if err := cropWand.CropImage(cropPreviewWidth, cropPreviewHeight, 0, cropPreviewY); err != nil {
		return nil, 0, fmt.Errorf("cropping preview: %w", err)
	}

	if err := composite.CompositeImage(cropWand, imagick.COMPOSITE_OP_OVER, true, 0, cropPreviewY); err != nil {
		return nil, 0, fmt.Errorf("compositing preview: %w", err)
	}

	w := int(composite.GetImageWidth())
	h := int(composite.GetImageHeight())
	pixels, err := composite.ExportImagePixels(0, 0, uint(w), uint(h), "RGBA", imagick.PIXEL_CHAR)
	if err != nil {
		return nil, 0, fmt.Errorf("exporting pixels: %w", err)
	}

	rgba, ok := pixels.([]uint8)
	if !ok {
		return nil, 0, fmt.Errorf("unexpected pixel type %T", pixels)
	}

	cellH := m.termDims.CellHeight
	stripW := barPxTotal + w
	cropStartPx := float64(m.yOffset) * m.scaleRatio
	cropEndPx := float64(m.yOffset+int(m.cropHeight)) * m.scaleRatio
	tickStartY := int(cropStartPx + 0.5)
	tickEndY := int(cropEndPx + 0.5)

	// Bar RGBA colors
	type rgba4 = [4]byte
	cropColor := rgba4{80, 130, 255, 255} // blue
	trackColor := rgba4{88, 88, 88, 255}  // dim gray

	strips := make([]string, m.previewRowCount)
	for row := range m.previewRowCount {
		pixelY := row * cellH
		stripH := min(cellH, h-pixelY)
		if stripH <= 0 {
			break
		}

		stripRGBA := make([]byte, stripW*stripH*4)

		for py := range stripH {
			absY := pixelY + py
			yf := float64(absY)
			inCrop := yf >= cropStartPx && yf < cropEndPx

			// Draw bar pixels
			for px := range barPxTotal {
				// Bar line: 1px track, 3px crop
				isLine := false
				if inCrop {
					isLine = px >= barLineCenter-barCropRadius && px <= barLineCenter+barCropRadius
				} else {
					isLine = px == barLineCenter
				}

				// Tick marks at crop boundaries
				isTick := (absY >= tickStartY && absY < tickStartY+barTickThick) ||
					(absY >= tickEndY-barTickThick && absY < tickEndY)
				isTick = isTick && px >= barTickStart && px <= barLineCenter

				if isLine || isTick {
					idx := (py*stripW + px) * 4
					c := trackColor
					if inCrop || isTick {
						c = cropColor
					}
					stripRGBA[idx] = c[0]
					stripRGBA[idx+1] = c[1]
					stripRGBA[idx+2] = c[2]
					stripRGBA[idx+3] = c[3]
				}
			}

			// Copy image pixels into the right portion of the strip
			imgRowStart := absY * w * 4
			dstStart := (py*stripW + barPxTotal) * 4
			copy(stripRGBA[dstStart:dstStart+w*4], rgba[imgRowStart:imgRowStart+w*4])
		}

		var buf bytes.Buffer
		writeKittyStrip(&buf, stripRGBA, stripW, stripH, kittyBaseID+row, m.imageCols)
		strips[row] = buf.String()
	}

	return strips, time.Since(start), nil
}

// writeKittyStrip writes one horizontal strip of RGBA pixels as a Kitty a=T command.
// Each strip gets a unique imageID so multiple strips can coexist on screen.
func writeKittyStrip(buf *bytes.Buffer, rgba []uint8, width, height, imageID, cols int) {
	const rawChunkSize = kittyChunkSize * 3 / 4

	totalChunks := (len(rgba) + rawChunkSize - 1) / rawChunkSize
	buf.Grow(len(rgba)*4/3 + totalChunks*24 + 64)

	encoded := make([]byte, base64.StdEncoding.EncodedLen(rawChunkSize))

	for i := range totalChunks {
		start := i * rawChunkSize
		end := min(start+rawChunkSize, len(rgba))

		n := base64.StdEncoding.EncodedLen(end - start)
		base64.StdEncoding.Encode(encoded[:n], rgba[start:end])

		more := byte('1')
		if i == totalChunks-1 {
			more = '0'
		}

		if i == 0 {
			buf.WriteString("\033_Gq=1,i=")
			buf.WriteString(strconv.Itoa(imageID))
			buf.WriteString(",a=T,f=32,s=")
			buf.WriteString(strconv.Itoa(width))
			buf.WriteString(",v=")
			buf.WriteString(strconv.Itoa(height))
			buf.WriteString(",c=")
			buf.WriteString(strconv.Itoa(cols))
			buf.WriteString(",r=1,m=")
			buf.WriteByte(more)
			buf.WriteByte(';')
		} else {
			buf.WriteString("\033_Gm=")
			buf.WriteByte(more)
			buf.WriteByte(';')
		}
		buf.Write(encoded[:n])
		buf.WriteString("\033\\")
	}
}

func (m model) saveCrop() error {
	mw := m.sourceWand.Clone()
	defer mw.Destroy()

	if err := mw.CropImage(m.cropWidth, m.cropHeight, 0, m.yOffset); err != nil {
		return fmt.Errorf("cropping: %w", err)
	}

	if err := mw.ResetImagePage(""); err != nil {
		return fmt.Errorf("resetting page: %w", err)
	}

	return mw.WriteImage(m.outputPath)
}
