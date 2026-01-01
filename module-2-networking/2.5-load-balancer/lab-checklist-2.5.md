# Lab 2.5 Checklist: Load Balancer

## Resources Created

- [ ] **Load Balancer**: `prod-skycraft-swc-lb` (Standard, Public)
- [ ] **Public IP**: `prod-skycraft-swc-pip` exists.

## Configuration Validation

- [ ] **Backend Pool**:
  - [ ] Name: `pool-worldservers`
  - [ ] Contains correct VMs (`vm-world-xx`)
- [ ] **Health Probe**:
  - [ ] Protocol: TCP
  - [ ] Port: 8085
  - [ ] Interval: 5 seconds
- [ ] **LB Rule**:
  - [ ] Port 8085 mapped to Backend Port 8085
  - [ ] Uses `pool-worldservers` and correct probe
  - [ ] Session Persistence is set to **Client IP**

## Functional Testing

- [ ] Verify VMs report "Healthy" in the Load Balancer insights/metrics.
- [ ] Attempt to connect to the Public IP on port 8085.
