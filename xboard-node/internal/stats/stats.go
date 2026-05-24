package stats

import (
	"encoding/json"
	"net/http"
	"sort"
	"sync"
)

// UserView is a single user's runtime stats on this node.
type UserView struct {
	UserID        int      `json:"user_id"`
	UUID          string   `json:"uuid,omitempty"`
	OnlineDevices int      `json:"online_devices"`
	UploadBytes   int64    `json:"upload_bytes"`
	DownloadBytes int64    `json:"download_bytes"`
	IPs           []string `json:"ips,omitempty"`
}

// NodeView is runtime stats for one node instance.
type NodeView struct {
	NodeID            int        `json:"node_id"`
	InstanceID        string     `json:"instance_id"`
	Protocol          string     `json:"protocol,omitempty"`
	Port              int        `json:"port,omitempty"`
	ActiveConnections int        `json:"active_connections"`
	UploadSpeedBps    int64      `json:"upload_speed_bps"`
	DownloadSpeedBps  int64      `json:"download_speed_bps"`
	Users             []UserView `json:"users"`
	OnlineUserCount   int        `json:"online_user_count"`
}

// Snapshot is the full stats payload exposed via HTTP.
type Snapshot struct {
	Nodes []NodeView `json:"nodes"`
}

var (
	mu      sync.RWMutex
	byNode  = make(map[int]*NodeView)
)

// Update replaces stats for a node instance.
func Update(v NodeView) {
	mu.Lock()
	defer mu.Unlock()
	cp := v
	cp.Users = append([]UserView(nil), v.Users...)
	byNode[v.NodeID] = &cp
}

// Remove drops stats for a stopped node.
func Remove(nodeID int) {
	mu.Lock()
	defer mu.Unlock()
	delete(byNode, nodeID)
}

// Get returns a copy of the current snapshot.
func Get() Snapshot {
	mu.RLock()
	defer mu.RUnlock()
	out := Snapshot{Nodes: make([]NodeView, 0, len(byNode))}
	ids := make([]int, 0, len(byNode))
	for id := range byNode {
		ids = append(ids, id)
	}
	sort.Ints(ids)
	for _, id := range ids {
		n := byNode[id]
		if n == nil {
			continue
		}
		cp := *n
		cp.Users = append([]UserView(nil), n.Users...)
		out.Nodes = append(out.Nodes, cp)
	}
	return out
}

// Handler serves GET /stats as JSON.
func Handler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(Get())
}
