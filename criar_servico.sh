#!/bin/bash

# ===============================
# Script para criar novo serviço Node.js com Nginx
# ===============================

# Verifica se está sendo executado como root
if [ "$EUID" -ne 0 ]; then
    echo "Por favor, execute como root (ou sudo)."
    exit 1
fi

# --- Parâmetros ---
PROJETO="$1"                # Nome do projeto
USUARIO="${2:-infra}"       # Usuário que vai rodar o serviço (default infra)
INICIO_PORTA=3000
FIM_PORTA=3100

if [ -z "$PROJETO" ]; then
    echo "Uso: $0 <nome-do-projeto> [usuario]"
    exit 1
fi

# --- Pastas ---
PASTA_PROJ="/home/$USUARIO/projetos/$PROJETO"

if [ -d "$PASTA_PROJ" ]; then
    echo "Erro: pasta $PASTA_PROJ já existe."
    exit 1
fi

mkdir -p "$PASTA_PROJ"
chown -R "$USUARIO":"$USUARIO" "$PASTA_PROJ"

# --- Busca portas ocupadas pelo Nginx ---
PORTAS_OCUPADAS=$(sudo ss -tlnp | grep nginx | awk '{print $4}' | awk -F':' '{print $NF}')

# --- Busca porta livre no intervalo ---
PORTA_DISPONIVEL=""
for ((port=INICIO_PORTA; port<=FIM_PORTA; port++)); do
    if ! echo "$PORTAS_OCUPADAS" | grep -q "^$port$"; then
        PORTA_DISPONIVEL=$port
        break
    fi
done

# --- Se não encontrou porta, pergunta ao usuário ---
if [ -z "$PORTA_DISPONIVEL" ]; then
    read -p "Todas as portas entre $INICIO_PORTA e $FIM_PORTA estão ocupadas. Digite uma porta manualmente: " PORTA_DISPONIVEL
fi

echo "Usando a porta $PORTA_DISPONIVEL para o projeto $PROJETO."

# --- Cria systemd service ---
SERVICE_FILE="/etc/systemd/system/$PROJETO.service"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=$PROJETO Node.js Service
After=network.target

[Service]
Type=simple
User=$USUARIO
WorkingDirectory=$PASTA_PROJ
ExecStart=/usr/bin/node index.js
Restart=always
RestartSec=3
Environment=NODE_ENV=production
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# --- Cria bloco Nginx ---
NGINX_FILE="/etc/nginx/sites-available/$PROJETO.conf"

cat > "$NGINX_FILE" <<EOF
server {
    listen $PORTA_DISPONIVEL;

    server_name _;

    location / {
        proxy_pass http://127.0.0.1:$PORTA_DISPONIVEL;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -s "$NGINX_FILE" /etc/nginx/sites-enabled/ 2>/dev/null || true

# --- Testa e recarrega Nginx ---
nginx -t && systemctl reload nginx

# --- Ativa service systemd ---
systemctl daemon-reload
systemctl enable "$PROJETO"
systemctl start "$PROJETO"

echo "=========================================="
echo "Projeto $PROJETO criado com sucesso!"
echo "Pasta: $PASTA_PROJ"
echo "Porta Nginx/Node: $PORTA_DISPONIVEL"
echo "Service systemd: $PROJETO.service"
echo "=========================================="
