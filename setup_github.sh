#!/bin/bash
# AI 产品定价监控 — GitHub 仓库初始化脚本
# 在任意电脑上执行一次即可

set -e

echo "🚀 初始化 AI 定价监控 GitHub 仓库..."

# 检查 git
if ! command -v git &> /dev/null; then
    echo "❌ 请先安装 git"
    exit 1
fi

# 检查 gh (GitHub CLI)
if ! command -v gh &> /dev/null; then
    echo "⚠️  未安装 GitHub CLI (gh)，将使用 git 手动模式"
    echo "   你需要先在 GitHub 网页上创建仓库: ai-pricing-monitor"
    echo "   然后输入你的 GitHub 用户名："
    read -p "GitHub 用户名: " GH_USER
    REPO_URL="https://github.com/${GH_USER}/ai-pricing-monitor.git"
else
    echo "📦 使用 GitHub CLI 创建仓库..."
    gh repo create ai-pricing-monitor --private --description "AI产品定价监控系统 - 136品牌定价追踪" || true
    REPO_URL=$(gh repo view ai-pricing-monitor --json url -q '.url').git
fi

# 初始化 git
cd "$(dirname "$0")"
git init
git add pricing_baseline.json SKILL.md README.md setup_github.sh
git add scan_history/ exports/ .gitkeep 2>/dev/null || true

# 创建 .gitignore
cat > .gitignore << 'EOF'
.DS_Store
*.tmp
__pycache__/
EOF
git add .gitignore

git commit -m "初始化 AI 定价监控仓库

- pricing_baseline.json: 136 产品定价基线
- SKILL.md: Claude Cowork 扫描任务定义
- scan_history/: 扫描历史快照
- exports/: Excel 导出文件"

git branch -M main
git remote add origin "$REPO_URL" 2>/dev/null || git remote set-url origin "$REPO_URL"
git push -u origin main

echo ""
echo "✅ 完成！仓库已推送到 GitHub"
echo "   在其他电脑上同步: git clone $REPO_URL"
echo "   在 Claude Cowork 中挂载该文件夹即可恢复扫描配置"
