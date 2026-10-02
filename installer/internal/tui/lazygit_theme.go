package tui

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/Gentleman-Programming/Gentleman.Dots/installer/internal/system"
)

func lazygitPlatform(m *Model) string {
	if m.SystemInfo.OS == system.OSMac {
		return "darwin"
	}
	return "linux"
}

// deployLazygitTheme copies the repository theme while retaining unrelated YAML settings.
// Ambiguous YAML layouts fail closed rather than risking loss of user configuration.
func deployLazygitTheme(repo, home, platform, xdg string) error {
	source, err := os.ReadFile(filepath.Join(repo, "config", "lazygit", "config.yml"))
	if err != nil {
		return fmt.Errorf("read Lazygit theme: %w", err)
	}
	theme := string(source)
	if !strings.Contains("\n"+theme, "\ngui:\n  theme:\n") {
		return fmt.Errorf("invalid repository Lazygit theme")
	}
	root := filepath.Join(home, ".config")
	if xdg != "" {
		root = xdg
	} else if platform == "darwin" {
		root = filepath.Join(home, "Library", "Application Support")
	}
	dest := filepath.Join(root, "lazygit", "config.yml")
	// Refuse symlinked destination directories: writing through them can escape
	// the chosen config root. An intentional symlink must be managed manually.
	for _, dir := range []string{root, filepath.Join(root, "lazygit")} {
		info, statErr := os.Lstat(dir)
		if statErr == nil && info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("Lazygit config directory is a symlink: %s", dir)
		}
		if statErr != nil && !os.IsNotExist(statErr) {
			return fmt.Errorf("inspect Lazygit config directory: %w", statErr)
		}
	}
	if info, statErr := os.Lstat(dest); statErr == nil && !info.Mode().IsRegular() {
		return fmt.Errorf("Lazygit config is not a regular file")
	} else if statErr != nil && !os.IsNotExist(statErr) {
		return fmt.Errorf("inspect Lazygit config: %w", statErr)
	}
	existing, err := os.ReadFile(dest)
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("read Lazygit config: %w", err)
	}
	output := theme
	if err == nil {
		output, err = mergeLazygitTheme(string(existing), theme)
		if err != nil {
			return fmt.Errorf("merge Lazygit config: %w", err)
		}
		if output == string(existing) {
			return nil
		}
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0755); err != nil {
		return fmt.Errorf("create Lazygit directory: %w", err)
	}
	mode := os.FileMode(0644)
	if info, statErr := os.Stat(dest); statErr == nil {
		if !info.Mode().IsRegular() {
			return fmt.Errorf("Lazygit config is not a regular file")
		}
		mode = info.Mode().Perm()
	}
	// A temporary sibling and rename avoid truncating an existing configuration on failure.
	temp, err := os.CreateTemp(filepath.Dir(dest), ".config-*.yml")
	if err != nil {
		return fmt.Errorf("prepare Lazygit config: %w", err)
	}
	defer os.Remove(temp.Name())
	if err = temp.Chmod(mode); err == nil {
		_, err = temp.WriteString(output)
	}
	if err == nil {
		err = temp.Close()
	} else {
		temp.Close()
	}
	if err != nil {
		return fmt.Errorf("write Lazygit config: %w", err)
	}
	if err := os.Rename(temp.Name(), dest); err != nil {
		return fmt.Errorf("replace Lazygit config: %w", err)
	}
	return nil
}

func mergeLazygitTheme(existing, source string) (string, error) {
	marker := "gui:\n  theme:\n"
	start := strings.Index(source, marker)
	if start > 0 && source[start-1] != '\n' {
		return "", fmt.Errorf("theme section not top-level")
	}
	if start < 0 {
		return "", fmt.Errorf("theme section missing")
	}
	block := source[start+len("gui:\n"):]
	lines := strings.SplitAfter(existing, "\n")
	guiStart, guiEnd := -1, len(lines)
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		if strings.HasPrefix(line, "gui:") {
			if strings.TrimSpace(line) != "gui:" {
				return "", fmt.Errorf("ambiguous gui section")
			}
			if guiStart >= 0 {
				return "", fmt.Errorf("duplicate gui section")
			}
			guiStart = i
		} else if !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "\t") && guiStart >= 0 && guiEnd == len(lines) {
			guiEnd = i
		}
	}
	if guiStart < 0 {
		return strings.TrimRight(existing, "\n") + "\n" + "gui:\n" + block, nil
	}
	themeStart, themeEnd := -1, guiEnd
	for i := guiStart + 1; i < guiEnd; i++ {
		line := lines[i]
		if strings.HasPrefix(line, "  theme:") {
			if strings.TrimSpace(line) != "theme:" || themeStart >= 0 {
				return "", fmt.Errorf("ambiguous theme section")
			}
			themeStart = i
		} else if themeStart >= 0 && themeEnd == guiEnd && strings.HasPrefix(line, "  ") && !strings.HasPrefix(line, "    ") && strings.TrimSpace(line) != "" {
			themeEnd = i
		}
	}
	if themeStart < 0 {
		lines = append(lines[:guiStart+1], append([]string{block}, lines[guiStart+1:]...)...)
	} else {
		lines = append(lines[:themeStart], append([]string{block}, lines[themeEnd:]...)...)
	}
	return strings.Join(lines, ""), nil
}
