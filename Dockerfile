# Define build arguments for platform-specific base images
ARG BASE_IMAGE_LINUX=mcr.microsoft.com/cbl-mariner/base/core:2.0
ARG BASE_IMAGE_WINDOWS=mcr.microsoft.com/windows/servercore:ltsc2022

# For Linux build
FROM ${BASE_IMAGE_LINUX} AS linux

WORKDIR /app

# Linux specific setup (can add more Linux dependencies here)
RUN tdnf update -y && \
    tdnf install -y git python3 && \
    tdnf clean all && \
    rm -rf /var/cache/tdnf /tmp/*

# For Windows build
FROM ${BASE_IMAGE_WINDOWS} AS windows

WORKDIR C:/app

# Windows specific setup (can add more Windows dependencies here)
RUN powershell -Command \
    Set-ExecutionPolicy Unrestricted -Scope Process -Force; \
    Invoke-WebRequest -Uri https://aka.ms/install-powershell.ps1 -OutFile install-powershell.ps1; \
    .\install-powershell.ps1 -Force; \
    Remove-Item -Force install-powershell.ps1

# Final stage to copy from the correct platform
FROM ${BASE_IMAGE_LINUX} AS final
COPY --from=linux /app /app

# Default entrypoint
CMD ["python3", "--version"]
