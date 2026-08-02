# Production App Workloads

Add production app overlays here after they have passed local and dev checks.

For example:

```yaml
resources:
  - ../../../../../apps/my-app/overlays/prod
```

Keep platform-owned services in the parent `apps/`, `platform/`, or
`infrastructure/` directories. This folder is for app-owned workloads.
