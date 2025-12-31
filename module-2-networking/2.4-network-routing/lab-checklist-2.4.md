# Lab 2.4 Checklist: Network Routing

## Resources Created

- [ ] **Route Table**: `prod-skycraft-swc-rt` exists.

## Configuration Validation

- [ ] **Route Created**:
  - [ ] Destination: `0.0.0.0/0`
  - [ ] Next Hop: Virtual Appliance (`10.0.2.4`)
- [ ] **Association**:
  - [ ] Linked to `AuthSubnet`
  - [ ] Linked to `WorldSubnet`
  - [ ] Linked to `DatabaseSubnet`

## Verification

- [ ] **Effective Routes** check on a VM NIC shows the UDR is active.
- [ ] **Connectivity**: Confirm internet access is blocked (or routed) as expected.
