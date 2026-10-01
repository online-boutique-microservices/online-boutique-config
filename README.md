# 📋 Online Boutique — GitOps Config Repository

> **Đây là Config Repo** cho hệ thống GitOps. ArgoCD watch repo này để triển khai
> ứng dụng Online Boutique lên Kubernetes (EKS).

## Cấu Trúc

```
online-boutique-config/
├── base/                    # K8s manifests gốc (11 services)
│   └── kustomization.yaml
├── envs/
│   ├── dev/                 # Dev overlay (auto-sync)
│   ├── staging/             # Staging overlay (auto-sync)
│   └── prod/                # Production overlay (manual sync)
├── argocd/
│   ├── projects/            # ArgoCD AppProject
│   └── applications/        # ArgoCD Applications (dev/staging/prod)
└── scripts/
    └── promote.sh           # Promote images: dev→staging→prod
```

## Cách Hoạt Động

1. **CI Pipeline** (trong App Repo) build images → push ECR → commit image tag mới vào `envs/dev/`
2. **ArgoCD** phát hiện commit mới → tự động sync lên EKS namespace `dev`
3. **Promote** bằng script: `./scripts/promote.sh dev staging`
4. **Production** yêu cầu manual sync trong ArgoCD UI

## Liên Kết

| Repo | Mục đích |
|:-----|:---------|
| **App Repo** (`microservices-demo`) | Source code + CI + Terraform |
| **Config Repo** (repo này) | K8s manifests + ArgoCD configs |

## Lưu Ý Quan Trọng

- **KHÔNG** chỉnh sửa `newTag` trong `kustomization.yaml` bằng tay — CI pipeline tự cập nhật
- **KHÔNG** chạy `kubectl apply` trực tiếp — mọi deploy phải qua Git → ArgoCD
- Thay `ACCOUNT_ID` bằng AWS Account ID thật trong tất cả `kustomization.yaml`
- Thay `YOUR_ORG` bằng GitHub org/username trong tất cả ArgoCD YAML
