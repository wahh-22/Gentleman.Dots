package tui

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDeployLazygitTheme(t *testing.T) {
	home := t.TempDir()
	repo := t.TempDir()
	source := filepath.Join(repo, "config", "lazygit")
	if err := os.MkdirAll(source, 0755); err != nil {
		t.Fatal(err)
	}
	theme := "gui:\n  theme:\n    defaultFgColor:\n      - '#DBE9FF'\n"
	if err := os.WriteFile(filepath.Join(source, "config.yml"), []byte(theme), 0644); err != nil {
		t.Fatal(err)
	}
	dest := filepath.Join(home, ".config", "lazygit", "config.yml")
	if err := os.MkdirAll(filepath.Dir(dest), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dest, []byte("git:\n  paging:\n    colorArg: always\ngui:\n  showIcons: false\n  theme:\n    defaultFgColor:\n      - red\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := deployLazygitTheme(repo, home, "linux", ""); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(dest)
	if err != nil {
		t.Fatal(err)
	}
	for _, text := range []string{"colorArg: always", "showIcons: false", "'#DBE9FF'"} {
		if !strings.Contains(string(data), text) {
			t.Errorf("missing %q: %s", text, data)
		}
	}
	if strings.Contains(string(data), "- red") {
		t.Errorf("old theme remains: %s", data)
	}
	if err := deployLazygitTheme(repo, home, "linux", ""); err != nil {
		t.Fatalf("repeat: %v", err)
	}
}

func TestDeployLazygitThemeRejectsUnsafeDestinations(t *testing.T) {
	for _, tc := range []struct {
		name, existing string
		link           string
	}{
		{"inline gui", "gui: {showIcons: false}\n", ""},
		{"gui ancestor symlink", "", ".config"},
		{"lazygit ancestor symlink", "", "lazygit"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			home, repo, outside := t.TempDir(), t.TempDir(), t.TempDir()
			sourceDir := filepath.Join(repo, "config", "lazygit")
			if err := os.MkdirAll(sourceDir, 0755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(sourceDir, "config.yml"), []byte("gui:\n  theme:\n    defaultFgColor: [blue]\n"), 0644); err != nil {
				t.Fatal(err)
			}
			dest := filepath.Join(home, ".config", "lazygit", "config.yml")
			if tc.link == ".config" {
				if err := os.Symlink(outside, filepath.Join(home, ".config")); err != nil {
					t.Skipf("symlinks unsupported: %v", err)
				}
			} else {
				if err := os.MkdirAll(filepath.Join(home, ".config"), 0755); err != nil {
					t.Fatal(err)
				}
				if tc.link == "lazygit" {
					if err := os.Symlink(outside, filepath.Join(home, ".config", "lazygit")); err != nil {
						t.Skipf("symlinks unsupported: %v", err)
					}
				}
			}
			if tc.existing != "" {
				if err := os.MkdirAll(filepath.Dir(dest), 0755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(dest, []byte(tc.existing), 0600); err != nil {
					t.Fatal(err)
				}
			}
			if err := deployLazygitTheme(repo, home, "linux", ""); err == nil {
				t.Fatal("expected fail-closed error")
			}
			if tc.existing != "" {
				data, err := os.ReadFile(dest)
				if err != nil || string(data) != tc.existing {
					t.Fatalf("existing config changed: %q, %v", data, err)
				}
			}
			if tc.link != "" {
				if _, err := os.Stat(filepath.Join(outside, "lazygit", "config.yml")); err == nil {
					t.Fatal("wrote through symlink")
				}
				if tc.link == "lazygit" {
					if _, err := os.Stat(filepath.Join(outside, "config.yml")); err == nil {
						t.Fatal("wrote through symlink")
					}
				}
			}
		})
	}
}

func TestMergeLazygitThemeBoundaries(t *testing.T) {
	source := "gui:\n  theme:\n    defaultFgColor: [blue]\n"
	for _, tc := range []struct {
		name, existing string
		wantError      bool
		preserve       string
	}{
		{"sibling after old theme", "gui:\n  theme:\n    defaultFgColor: [red]\n  showIcons: false\ngit:\n  autoFetch: false\n", false, "showIcons: false\ngit:"},
		{"duplicate gui", "gui:\n  showIcons: false\ngui:\n  theme: {}\n", true, ""},
		{"inline theme", "gui:\n  theme: { defaultFgColor: red }\n", true, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			merged, err := mergeLazygitTheme(tc.existing, source)
			if (err != nil) != tc.wantError {
				t.Fatalf("merge error %v, output %q", err, merged)
			}
			if err == nil && (strings.Count(merged, "gui:") != 1 || strings.Count(merged, "  theme:") != 1 || strings.Contains(merged, "[red]") || !strings.Contains(merged, tc.preserve)) {
				t.Fatalf("malformed merge: %q", merged)
			}
		})
	}
}

func TestDeployRepositoryLazygitTheme(t *testing.T) {
	home := t.TempDir()
	if err := deployLazygitTheme(filepath.Join("..", "..", ".."), home, "darwin", ""); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(home, "Library", "Application Support", "lazygit", "config.yml"))
	if err != nil {
		t.Fatal(err)
	}
	source, err := os.ReadFile(filepath.Join("..", "..", "..", "config", "lazygit", "config.yml"))
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != string(source) {
		t.Fatal("installed theme differs from repo asset")
	}
}

func TestDeployLazygitThemeDestinationsAndFailures(t *testing.T) {
	for _, tc := range []struct{ name, platform, xdg string }{{"mac", "darwin", ""}, {"linux", "linux", ""}, {"xdg", "darwin", "custom"}} {
		t.Run(tc.name, func(t *testing.T) {
			home, repo := t.TempDir(), t.TempDir()
			if err := os.MkdirAll(filepath.Join(repo, "config", "lazygit"), 0755); err != nil {
				t.Fatal(err)
			}
			source := filepath.Join(repo, "config", "lazygit", "config.yml")
			if err := os.WriteFile(source, []byte("gui:\n  theme:\n    defaultFgColor: [blue]\n"), 0644); err != nil {
				t.Fatal(err)
			}
			xdg := tc.xdg
			if xdg != "" {
				xdg = filepath.Join(home, xdg)
			}
			if err := deployLazygitTheme(repo, home, tc.platform, xdg); err != nil {
				t.Fatal(err)
			}
			root := filepath.Join(home, ".config")
			if tc.platform == "darwin" {
				root = filepath.Join(home, "Library", "Application Support")
			}
			if xdg != "" {
				root = xdg
			}
			if _, err := os.Stat(filepath.Join(root, "lazygit", "config.yml")); err != nil {
				t.Fatal(err)
			}
		})
	}
	t.Run("missing source does not overwrite", func(t *testing.T) {
		home := t.TempDir()
		dest := filepath.Join(home, ".config", "lazygit", "config.yml")
		if err := os.MkdirAll(filepath.Dir(dest), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(dest, []byte("git: keep\n"), 0600); err != nil {
			t.Fatal(err)
		}
		if err := deployLazygitTheme(t.TempDir(), home, "linux", ""); err == nil {
			t.Fatal("expected source error")
		}
		data, _ := os.ReadFile(dest)
		if string(data) != "git: keep\n" {
			t.Fatalf("overwritten: %q", data)
		}
	})
	t.Run("ambiguous user theme does not overwrite", func(t *testing.T) {
		merged, err := mergeLazygitTheme("gui:\n  theme: { custom: true }\n", "gui:\n  theme:\n    defaultFgColor: [blue]\n")
		if err == nil {
			t.Fatalf("expected error, got %q", merged)
		}
	})
}
