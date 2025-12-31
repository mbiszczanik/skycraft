# Lab 2.4 Checklist: Network Routing

## Resources Created

- [ ] **Route Table**: `prod-skycraft-swc-rt` exists.

## Configuration Validation

- [ ] **Route Created**:
  - [ ] Destination: `0.0.0.0/0`
  - [ ] Next Hop: Virtual Appliance (`10.0.1.4`)
- [ ] **Association**:
  - [ ] Linked to `snet-auth`
  - [ ] Linked to `snet-world`
  - [ ] Linked to `snet-db`

## Verification

- [ ] **Effective Routes** check on a VM NIC shows the UDR is active.
- [ ] **Connectivity**: Confirm internet access is blocked (or routed) as expected.
