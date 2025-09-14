#────────────────────────────────────────────────────────────
#  🏗️ CUSTOM DEV IMAGE: C/JAVA/PYTHON + LATEX + MAKE
#────────────────────────────────────────────────────────────

FROM lscr.io/linuxserver/code-server:latest

# Use bash shell (required for SDKMAN)
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

# Install development tools and compilers
RUN apt-get update && apt-get install -y \
    # C development tools
    build-essential \
    make \
    gdb \
    valgrind \
    # Python development
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    # LaTeX document generation
    texlive-latex-base \
    texlive-latex-recommended \
    texlive-latex-extra \
    texlive-fonts-recommended \
    texlive-fonts-extra \
    texlive-xetex \
    # Java (base JDK for SDKMAN)
    default-jdk \
    # Essential utilities
    git \
    curl \
    wget \
    unzip \
    zip \
    tree \
    htop \
    neofetch \
    pandoc \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip and install Python data science stack
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel \
    && pip3 install --no-cache-dir \
        virtualenv \
        pipenv 

# Install SDKMAN for Java version management
RUN curl -s "https://get.sdkman.io" | bash

# Configure SDKMAN environment
RUN echo 'export SDKMAN_DIR="/root/.sdkman"' >> /root/.bashrc \
    && echo 'source "/root/.sdkman/bin/sdkman-init.sh"' >> /root/.bashrc

# Install Java versions via SDKMAN
RUN bash -c "source /root/.sdkman/bin/sdkman-init.sh \
    && sdk install java 8.0.402-tem \
    && sdk install java 21.0.2-tem 

# Install Java build tools
RUN bash -c "source /root/.sdkman/bin/sdkman-init.sh \
    && sdk install maven \
    && sdk install gradle"

# Create development directories
RUN mkdir -p /config/workspace/{c-projects,java-projects,python-projects,notebooks,latex-docs}

# Create enhanced startup script with extensions
RUN cat > /init-dev-env.sh << 'EOF'
#!/bin/bash
echo "🚀 Initializing C/Java/Python development environment..."

# VSCode Extensions for C/Java/Python development
EXTENSIONS=(
    # Python development
    ms-python.python
    ms-toolsai.jupyter
    # Java development  
    redhat.java
    vscjava.vscode-java-pack
    vscjava.vscode-maven
    vscjava.vscode-gradle
    # C/C++ development
    ms-vscode.cpptools
    ms-vscode.cmake-tools
    # LaTeX
    James-Yu.latex-workshop
    # General development
    ms-vscode.vscode-json
    esbenp.prettier-vscode
    ms-vscode.hexeditor
)

# Install extensions (they'll persist in mounted /config)
echo "📦 Installing/updating VSCode extensions..."
for ext in "${EXTENSIONS[@]}"; do
    if ! code-server --list-extensions | grep -q "^$ext\$"; then
        echo "  Installing: $ext"
        code-server --install-extension "$ext" &
    else
        echo "  Already installed: $ext"
    fi
    sleep 1
done

# Wait for all background installs to complete
wait
echo "✅ Extensions installed successfully!"

# Source SDKMAN
source /root/.sdkman/bin/sdkman-init.sh

# Create Python virtual environments if they don't exist
if [ ! -d "/config/workspace/python-projects/venvs/datascience" ]; then
    echo "🐍 Creating Python virtual environments..."
    mkdir -p /config/workspace/python-projects/venvs
    
    python3 -m venv /config/workspace/python-projects/venvs/datascience
    source /config/workspace/python-projects/venvs/datascience/bin/activate
    pip install jupyter pandas numpy matplotlib seaborn scikit-learn plotly
    deactivate
if 

if [ ! -d "/config/workspace/python-projects/venvs/general" ]; then
    python3 -m venv /config/workspace/python-projects/venvs/general
    source /config/workspace/python-projects/venvs/general/bin/activate
    pip install requests beautifulsoup4 flask fastapi pytest black flake8
    deactivate
fi

echo ""
echo "🎉 Development environment ready!"
echo ""
echo "🔧 Available Tools:"
echo "  🔨 C/C++: gcc $(gcc --version | head -n1 | awk '{print $4}')"
echo "  🔧 Make: $(make --version | head -n1)"
echo "  ☕ Java: $(java -version 2>&1 | head -n1)"
echo "  🐍 Python: $(python3 --version)"
echo "  📊 Jupyter Lab/Notebook"
echo "  📄 LaTeX (texlive)"
echo "  🛠️  Build Tools: Maven, Gradle"
echo ""
echo "📁 Project Structure:"
echo "  🔨 C Projects: /config/workspace/c-projects/"
echo "  ☕ Java Projects: /config/workspace/java-projects/"
echo "  🐍 Python Projects: /config/workspace/python-projects/"
echo "  📊 Notebooks: /config/workspace/notebooks/"
echo "  📄 LaTeX Documents: /config/workspace/latex-docs/"
echo ""
echo "🐍 Python Virtual Environments:"
echo "  📊 Data Science: source /config/workspace/python-projects/venvs/datascience/bin/activate"
echo "  🔧 General Dev: source /config/workspace/python-projects/venvs/general/bin/activate"
echo ""
echo "☕ Java Version Management:"
sdk list java | grep installed || echo "  Use 'sdk list java' and 'sdk use java VERSION' to switch versions"
echo ""
echo "🚀 Ready to develop in C, Java, and Python!"
EOF

RUN chmod +x /init-dev-env.sh

# Set default workspace
ENV DEFAULT_WORKSPACE=/config/workspace

# Expose code-server port
EXPOSE 8443

# Use LinuxServer init system
ENTRYPOINT ["/init"]
