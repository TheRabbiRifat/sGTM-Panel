package commands

import (
	"context"
	"errors"
	"fmt"
	"strconv"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/network"
	"github.com/docker/docker/client"
	"github.com/docker/go-connections/nat"
)

// Spec describes a service that should exist on this node.
type Spec struct {
	ContainerName string
	Image         string
	Env           map[string]string
	CPULimit      float64
	RAMLimitMB    int
	Labels        map[string]string
	Networks      []string
	ServiceID     string // Hostaffin service UUID (for labels)
	Port          int    // internal port the container listens on (default 8080)
}

// DeployResult is reported back to the control plane.
type DeployResult struct {
	ServiceID     string `json:"service_id"`
	NodeID        string `json:"node_id"`
	ContainerID   string `json:"container_id"`
	ContainerName string `json:"container_name"`
	OK            bool   `json:"ok"`
	Error         string `json:"error,omitempty"`
}

// Deploy creates + starts a container from the spec.
func Deploy(ctx context.Context, cli *client.Client, spec Spec) (DeployResult, error) {
	if spec.ContainerName == "" {
		return DeployResult{}, errors.New("container_name required")
	}
	if spec.Image == "" {
		spec.Image = "gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable"
	}
	if spec.Port == 0 {
		spec.Port = 8080
	}

	env := make([]string, 0, len(spec.Env))
	for k, v := range spec.Env {
		env = append(env, k+"="+v)
	}

	// Resource limits
	memBytes := int64(spec.RAMLimitMB) * 1024 * 1024
	pidsLimit := int64(256)
	hostCfg := &container.HostConfig{
		Resources: container.Resources{
			Memory:    memBytes,
			CPUQuota:  int64(spec.CPULimit * 100000.0),
			CPUPeriod: 100000,
			PidsLimit: &pidsLimit,
		},
		RestartPolicy: container.RestartPolicy{
			Name:              "on-failure",
			MaximumRetryCount: 5,
		},
		NetworkMode: "hostaffin_edge",
	}

	cfg := &container.Config{
		Image: spec.Image,
		Env:   env,
		Labels: mergeLabels(spec.Labels, map[string]string{
			"hostaffin.service_id": spec.ServiceID,
			"hostaffin.managed":    "true",
		}),
		ExposedPorts: nat.PortSet{
			nat.Port(strconv.Itoa(spec.Port) + "/tcp"): struct{}{},
		},
	}

	resp, err := cli.ContainerCreate(ctx, cfg, hostCfg, &network.NetworkingConfig{
		EndpointsConfig: map[string]*network.EndpointSettings{
			"hostaffin_edge": {NetworkID: "hostaffin_edge"},
		},
	}, nil, spec.ContainerName)
	if err != nil {
		return DeployResult{ServiceID: spec.ServiceID}, fmt.Errorf("create: %w", err)
	}
	if err := cli.ContainerStart(ctx, resp.ID, types.ContainerStartOptions{}); err != nil {
		return DeployResult{ServiceID: spec.ServiceID, ContainerID: resp.ID}, fmt.Errorf("start: %w", err)
	}
	return DeployResult{
		ServiceID:     spec.ServiceID,
		ContainerID:   resp.ID,
		ContainerName: spec.ContainerName,
		OK:            true,
	}, nil
}

// Restart restarts the named container.
func Restart(ctx context.Context, cli *client.Client, name string) error {
	return cli.ContainerRestart(ctx, name, container.StopOptions{})
}

// Delete removes the container.
func Delete(ctx context.Context, cli *client.Client, name string) error {
	return cli.ContainerRemove(ctx, name, types.ContainerRemoveOptions{
		Force: true,
	})
}

func mergeLabels(a, b map[string]string) map[string]string {
	out := make(map[string]string, len(a)+len(b))
	for k, v := range a {
		out[k] = v
	}
	for k, v := range b {
		out[k] = v
	}
	return out
}