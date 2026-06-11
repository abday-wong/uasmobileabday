# GitHub Remote Pusher Helper Script
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "     UAS MOBILE PROGRAMMING - GITHUB REPOSITORY PUSHER    " -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host ""

# 1. Ask for Remote URL
$remoteUrl = Read-Host "Enter your target GitHub Repository URL (e.g., https://github.com/username/your-repo.git)"
$remoteUrl = $remoteUrl.Trim()

if (-not $remoteUrl) {
    Write-Host "Error: GitHub Repository URL cannot be empty." -ForegroundColor Red
    Exit
}

Write-Host "`nSetting up remote..." -ForegroundColor Cyan
# Check if remote origin already exists
$existingRemote = git remote get-url origin 2>$null

if ($existingRemote) {
    Write-Host "Existing remote origin found ($existingRemote). Updating to new URL..." -ForegroundColor Yellow
    git remote set-url origin $remoteUrl
} else {
    Write-Host "Adding remote origin..." -ForegroundColor Yellow
    git remote add origin $remoteUrl
}

# 2. Push all branches
Write-Host "`nPushing all 5 branches to GitHub..." -ForegroundColor Cyan
Write-Host "This will push main, develop, and all feature/ branches." -ForegroundColor Gray

# Array of branches to push
$branches = @("main", "develop", "feature/backend", "feature/ecommerce", "feature/wallet")

foreach ($branch in $branches) {
    Write-Host "`n[+] Pushing branch '$branch'..." -ForegroundColor Yellow
    # Check if branch exists locally
    $branchExists = git branch --list $branch
    if ($branchExists) {
        git checkout $branch
        git push -u origin $branch --force
    } else {
        Write-Host "Warning: Branch '$branch' not found locally." -ForegroundColor Red
    }
}

# Go back to main
git checkout main

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Success! All branches pushed to your GitHub repository. " -ForegroundColor Green
Write-Host "  GitHub Repo URL: $remoteUrl" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green

# Pusher updated.

