package config

import "testing"

func TestPanelFailClosedEnabled(t *testing.T) {
	standalone := &Config{Standalone: &StandaloneConfig{Enabled: true}}
	if standalone.PanelFailClosedEnabled() {
		t.Fatal("standalone should not fail closed")
	}

	defaults := &Config{}
	if !defaults.PanelFailClosedEnabled() {
		t.Fatal("panel fail closed should default to true")
	}

	disabled := false
	explicit := &Config{Node: NodeConfig{PanelFailClosed: &disabled}}
	if explicit.PanelFailClosedEnabled() {
		t.Fatal("panel_fail_closed=false should disable fail closed")
	}
}

func TestPanelGracePeriodDuration(t *testing.T) {
	cfg := &Config{}
	if cfg.PanelGracePeriodDuration().Seconds() != 90 {
		t.Fatalf("expected 90s default, got %v", cfg.PanelGracePeriodDuration())
	}
	cfg.Node.PanelGracePeriod = 30
	if cfg.PanelGracePeriodDuration().Seconds() != 30 {
		t.Fatalf("expected 30s, got %v", cfg.PanelGracePeriodDuration())
	}
}
