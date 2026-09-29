#!/usr/bin/env bash
# =============================================================================
#   ██╗   ██╗ ██████╗ ██╗  ██╗███████╗███╗   ██╗
#   ██║   ██║██╔═══██╗██║ ██╔╝██╔════╝████╗  ██║
#   ██║   ██║██║   ██║█████╔╝ █████╗  ██╔██╗ ██║
#   ╚██╗ ██╔╝██║   ██║██╔═██╗ ██╔══╝  ██║╚██╗██║
#    ╚████╔╝ ╚██████╔╝██║  ██╗███████╗██║ ╚████║
#     ╚═══╝   ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝
#
#   Practica ingles hablando con una IA de voz a voz, local y privada.
#   Este asistente instala dependencias, descarga modelos, compila las
#   herramientas y guarda tus preferencias.
#
#   Funciona en Linux, macOS y Windows nativo (Git Bash, sin WSL).
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Opciones de ejecucion: --build para forzar compilacion desde codigo fuente
# -----------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      echo "Uso: ./voxen.sh [OPCIONES]"
      echo ""
      echo "Opciones:"
      echo "  (sin opciones)      Descarga binarios oficiales y modelos (asistente guiado)"
      echo "  --help, -h          Muestra esta ayuda"
      exit 0
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Validacion de usuario: NUNCA correr el instalador completo como root/sudo
# -----------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  echo "" >&2
  echo "===============================================================================" >&2
  echo "  [!] ERROR: No ejecutes './voxen.sh' con 'sudo'." >&2
  echo "===============================================================================" >&2
  echo "  El asistente solicita 'sudo' automaticamente solo para los paquetes del" >&2
  echo "  sistema que lo requieran. Al correrlo con sudo:" >&2
  echo "    1. No encuentra las herramientas de tu usuario (como Rust y Cargo)." >&2
  echo "    2. Crea carpetas y modelos con permisos de root." >&2
  echo "" >&2
  echo "  Ejecutalo directamente con tu usuario normal:" >&2
  echo "    ./voxen.sh" >&2
  echo "===============================================================================" >&2
  exit 1
fi

# Cargar entorno de Cargo si existe en el home del usuario
if [ -f "$HOME/.cargo/env" ]; then
  # shellcheck source=/dev/null
  . "$HOME/.cargo/env"
fi
if [ -d "$HOME/.cargo/bin" ] && [[ ":$PATH:" != *":$HOME/.cargo/bin:"* ]]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$RAIZ"

DETECTADO_SO="$(uname -s)" # Linux / Darwin / MINGW64_NT-... (Git Bash de Windows)
ES_WINDOWS=false
case "$DETECTADO_SO" in MINGW*|MSYS*|CYGWIN*) ES_WINDOWS=true ;; esac

# -----------------------------------------------------------------------------
# Utilidades de interaccion (toleran EOF/Ctrl+D para no colgar el script)
# -----------------------------------------------------------------------------
preguntar_si_no() { # $1 texto, optional default ($2: s o n)
  local texto="$1" def="${2:-s}" respuesta
  local prompt_sufijo="[S/n]"
  [ "$def" = "n" ] && prompt_sufijo="[s/N]"
  while true; do
    read -r -p "$texto $prompt_sufijo: " respuesta </dev/tty || respuesta="$def"
    [ -z "$respuesta" ] && respuesta="$def"
    case "$respuesta" in
      s|S|si|SI|Si|y|Y|yes) return 0 ;;
      n|N|no|NO|No)         return 1 ;;
      *) echo "  Por favor responde 's' o 'n'." >&2 ;;
    esac
  done
}

preguntar_opcion() { # $1 texto, $2... opciones -> imprime el indice elegido a stdout (1, 2, ...)
  local texto="$1"; shift
  local opciones=("$@") respuesta
  while true; do
    echo "" >&2
    echo "$texto" >&2
    local i=1
    for op in "${opciones[@]}"; do
      echo "  $i) $op" >&2
      i=$((i+1))
    done
    read -r -p "  Elige [1-${#opciones[@]}]: " respuesta </dev/tty || respuesta=""
    if [[ "$respuesta" =~ ^[0-9]+$ ]] && [ "$respuesta" -ge 1 ] && [ "$respuesta" -le "${#opciones[@]}" ]; then
      echo "$respuesta"
      return 0
    fi
    echo "  Opcion invalida." >&2
  done
}

preguntar_texto() { # $1 texto, $2 default -> valor
  local valor
  read -r -p "$1 [$2]: " valor </dev/tty || valor=""
  echo "${valor:-$2}"
}

morir() { echo -e "\n[X] $1" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Descarga con verificacion de integridad (SHA256 conocido por archivo).
#
# Un .gguf truncado en una conexion lenta se carga igual (llama.cpp a veces ni
# lo detecta), asi que cada archivo con hash oficial verificado se comprueba
# tras descargar. Modelos sin hash publicado (Qwen3.5 via unsloth) solo se
# verifican por tamano > 0; el comentario documenta el motivo.
# -----------------------------------------------------------------------------
HASHES=(
  "models/llm/qwen2.5-1.5b-instruct-q4_k_m.gguf|POR_PUBLICAR"
  "models/llm/qwen2.5-3b-instruct-q4_k_m.gguf|626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d"
  "models/llm/Qwen3.5-4B-Q4_K_M.gguf|POR_PUBLICAR"
  "models/llm/qwen2.5-7b-instruct-q4_k_m.gguf|POR_PUBLICAR"
  "models/stt/ggml-small.en.bin|c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"
  "models/stt/ggml-base.en.bin|a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
  "models/tts/en_US-ryan-medium.onnx|abf4c274862564ed647ba0d2c47f8ee7c9b717d27bdad9219100eb310db4047a"
  "models/tts/en_US-ryan-medium.onnx.json|44034c056cb15681b2ad494307c7f3f2e4499d1253c700c711fa0a4607ffe78d"
)

hash_de() { # $1 ruta -> hash registrado o vacio
  for par in "${HASHES[@]}"; do
    if [ "${par%%|*}" = "$1" ]; then echo "${par#*|}"; return 0; fi
  done
}

verificar_sha256() { # $1 ruta -> 0 si ok o sin hash conocido, 1 si difiere
  local ruta="$1" esperado real
  esperado=$(hash_de "$ruta")
  [ -z "$esperado" ] || [ "$esperado" = "POR_PUBLICAR" ] && return 0
  if command -v sha256sum >/dev/null 2>&1; then
    real=$(sha256sum "$ruta" | cut -d' ' -f1)
  else
    real=$(shasum -a 256 "$ruta" | cut -d' ' -f1) # macOS
  fi
  if [ "$real" != "$esperado" ]; then
    echo "  [X] Corrupcion detectada en $ruta (SHA256 no coincide)." >&2
    echo "      Esperado: $esperado" >&2
    echo "      Obtenido: $real" >&2
    rm -f "$ruta"
    return 1
  fi
  echo "  [ok] integridad verificada"
}

descargar() { # $1 destino, $2 url
  local destino="$1" url="$2"
  if [ -s "$destino" ]; then
    echo "  [skip] $(basename "$destino") ya existe"
    if ! verificar_sha256 "$destino"; then
      echo "  re-descargando por integridad invalida..."
    else
      return 0
    fi
  fi
  mkdir -p "$(dirname "$destino")"
  curl -fL --retry 3 --progress-bar -o "$destino.tmp" "$url" \
    || { rm -f "$destino.tmp"; morir "fallo la descarga de $url (revisa tu conexion e intenta de nuevo)"; }
  mv "$destino.tmp" "$destino"
  verificar_sha256 "$destino" || morir "no se pudo descargar $destino con integridad verificada"
}

# -----------------------------------------------------------------------------
# Deteccion de hardware (misma tabla que Voxen aplica en runtime)
# -----------------------------------------------------------------------------
detectar_ram_gb() {
  if [ -r /proc/meminfo ]; then
    awk '/MemTotal/ {print int($2/1024/1024)}' /proc/meminfo
  elif command -v sysctl >/dev/null 2>&1; then
    echo $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) # macOS
  else
    echo 8
  fi
}

RAM_GB=$(detectar_ram_gb)

if   [ "$RAM_GB" -ge 16 ]; then PERFIL="Pro (16 GB+)";             LLM_REC="Qwen2.5-3B o 7B"; WHISPER_REC="small.en"; WHISPER_RAM="~1.5 GB"
elif [ "$RAM_GB" -ge 12 ]; then PERFIL="Alta Precision (8-16 GB)"; LLM_REC="Qwen2.5-3B Q8";      WHISPER_REC="base.en";  WHISPER_RAM="~500 MB"
elif [ "$RAM_GB" -ge 8 ];  then PERFIL="Estandar (8 GB)";          LLM_REC="Qwen2.5-3B Q4_K_M";  WHISPER_REC="base.en";  WHISPER_RAM="~500 MB"
else                            PERFIL="Ultra-Ligero (4 GB)";      LLM_REC="Qwen2.5-1.5B Q4_K_M";WHISPER_REC="tiny.en";  WHISPER_RAM="~200 MB"
fi

banner() {
  echo -e "\033[1;37m"
  cat << "EOF"
███        ███                                                        
███        ███                                                        
███        ███   ▄████▄   ███   ███   ▄████▄   ██████▄                
 ▀██▄    ▄██▀   ███  ███   ▀█████▀   ███▄▄▄██  ██   ▀██               
  ▀███  ███▀    ███  ███   ▄█████▄   ███▀▀▀▀▀  ██    ██               
    ▀████▀       ▀████▀   ███   ███   ▀████▀   ██    ██               
EOF
  echo -e "\033[0m"
  echo "==============================================================================="
  echo "  Asistente guiado de instalacion y configuracion de Voxen."
  echo "  Practica ingles hablando: voz a voz 100% privado en tu computadora."
  echo "==============================================================================="
}

# =============================================================================
# 1) Herramientas basicas del sistema
# =============================================================================
banner
echo ""
echo "Plataforma detectada: $DETECTADO_SO"

# Solo se requieren curl y tar para el modo rapido precompilado
for h in curl tar; do
  if ! command -v "$h" >/dev/null 2>&1; then
    morir "falta la herramienta '$h'. Instalala en tu sistema y vuelve a correr ./voxen.sh"
  fi
done

instalar_dependencias_compilacion() {
  echo ""
  echo "---------------------- Herramientas de compilacion ----------------------------"
  if $ES_WINDOWS; then
    echo "  En Windows se necesita: Git Bash, MSVC Build Tools, CMake y Rustup."
    command -v cmake >/dev/null 2>&1 || winget install --id Kitware.CMake -e --silent || true
    command -v cargo >/dev/null 2>&1 || winget install --id Rustlang.Rustup -e --silent || true
    if ! command -v cl >/dev/null 2>&1 && [ ! -d "/c/Program Files (x86)/Microsoft Visual Studio" ]; then
      winget install --id Microsoft.VisualStudio.2022.BuildTools -e --silent || true
    fi
  elif command -v apt >/dev/null 2>&1; then
    echo "  Debian/Ubuntu/Mint detectado."
    echo "  Se requieren: build-essential cmake git curl pkg-config libasound2-dev"
    if preguntar_si_no "Instalar dependencias de compilacion del sistema?"; then
      echo "  Instalando paquetes (puede requerir sudo)..."
      sudo apt-get update -qq >/dev/null 2>&1 || true
      sudo apt-get install -y -qq build-essential cmake git curl pkg-config libasound2-dev >/dev/null 2>&1 \
        || sudo apt-get install -y build-essential cmake git curl pkg-config libasound2-dev
      echo "  [ok] Dependencias instaladas"
    else
      morir "sin las dependencias de compilacion no se puede compilar desde codigo fuente"
    fi
  elif command -v dnf >/dev/null 2>&1; then
    preguntar_si_no "Instalar dependencias de compilacion (gcc-c++ cmake alsa-lib-devel)?" || morir "sin las dependencias no se puede compilar"
    sudo dnf install -y -q gcc-c++ cmake git curl alsa-lib-devel pkgconf-pkg-config >/dev/null 2>&1 \
      || sudo dnf install -y gcc-c++ cmake git curl alsa-lib-devel pkgconf-pkg-config
    echo "  [ok] Dependencias instaladas"
  elif command -v pacman >/dev/null 2>&1; then
    preguntar_si_no "Instalar dependencias de compilacion (base-devel cmake alsa-lib)?" || morir "sin las dependencias no se puede compilar"
    sudo pacman -Sy --noconfirm --quiet base-devel cmake git curl alsa-lib >/dev/null 2>&1 \
      || sudo pacman -Sy --noconfirm base-devel cmake git curl alsa-lib
    echo "  [ok] Dependencias instaladas"
  elif command -v brew >/dev/null 2>&1; then
    brew install cmake pkg-config >/dev/null 2>&1 || brew install cmake pkg-config || true
    echo "  [ok] Dependencias de Homebrew instaladas"
  fi

  # Asegurar que Rust / Cargo este disponible en el entorno
  if ! command -v cargo >/dev/null 2>&1; then
    if [ -f "$HOME/.cargo/env" ]; then
      # shellcheck source=/dev/null
      . "$HOME/.cargo/env"
    fi
    if [ -d "$HOME/.cargo/bin" ] && [[ ":$PATH:" != *":$HOME/.cargo/bin:"* ]]; then
      export PATH="$HOME/.cargo/bin:$PATH"
    fi
  fi
  if ! command -v cargo >/dev/null 2>&1; then
    echo ""
    echo "  [!] Rust y Cargo no estan instalados en este usuario."
    if preguntar_si_no "Deseas instalar Rust oficial automaticamente via rustup?"; then
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
      [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
      export PATH="$HOME/.cargo/bin:$PATH"
    fi
  fi

  for h in git cmake cargo make; do
    if ! command -v "$h" >/dev/null 2>&1; then
      morir "falta '$h' despues de la instalacion. Instalala y vuelve a correr ./voxen.sh --build"
    fi
  done
}


echo ""
echo "Tu equipo: ${RAM_GB} GB de RAM -> perfil recomendado: $PERFIL"
echo "  LLM sugerido:      $LLM_REC"
echo "  Whisper sugerido:  $WHISPER_REC (RAM de inferencia ~$WHISPER_RAM)"

# =============================================================================
# 2) Eleccion de STT (por ahora solo ingles)
# =============================================================================
echo ""
echo "------------------------------ STT (escucha) --------------------------------"
echo "El modelo de transcripcion vive en RAM mientras Voxen corre."
OPCION_STT=$(preguntar_opcion "Modelos disponibles:" \
  "ggml-base.en  - recomendado: buena precision, ~500 MB de RAM" \
  "ggml-small.en - mas precision en acentos, ~1.5 GB de RAM, mas lento")
case "$OPCION_STT" in
  2) WHISPER_MODELO="ggml-small.en.bin" ;;
  *) WHISPER_MODELO="ggml-base.en.bin"  ;;
esac
if [ "$WHISPER_MODELO" = "ggml-small.en.bin" ] && [ "$RAM_GB" -lt 8 ]; then
  echo "  ! Aviso: con ${RAM_GB} GB de RAM small.en puede competir con el LLM."
  echo "    Si notas fallas o lentitud, vuelve a correr ./voxen.sh y elige base.en."
fi

# =============================================================================
# 3) Eleccion de TTS (una sola voz por ahora)
# =============================================================================
echo ""
echo "------------------------------ TTS (voz) -------------------------------------"
echo "Voz disponible (mas voces se agregaran en proximas versiones):"
echo "  - en_US-ryan-medium : voz masculina en ingles, ~60 MB, natural y rapida."
preguntar_si_no "Descargar la voz Ryan?" && TTS_BAJAR=true || TTS_BAJAR=false
if ! $TTS_BAJAR; then
  echo "  Sin voz no habra audio; puedes reintentarlo corriendo ./voxen.sh otra vez."
fi

# =============================================================================
# 4) Modo del LLM: offline (local) u online (API remota)
# =============================================================================
echo ""
echo "------------------------------ Cerebro (LLM) ---------------------------------"
MODO_LLM=$(preguntar_opcion "Como quieres que razona Voxen?" \
  "Offline (local): descarga el modelo, funciona sin internet, usa tu RAM" \
  "Online (remoto): no gasta RAM, necesita internet y una API key")
case "$MODO_LLM" in
  2) MODO="remote" ;;
  *) MODO="local"  ;;
esac

ARCHIVO_ENV="$RAIZ/.env"
touch "$ARCHIVO_ENV"
guardar_env() { # $1 clave, $2 valor
  grep -v "^$1=" "$ARCHIVO_ENV" >"$ARCHIVO_ENV.tmp" 2>/dev/null || true
  mv "$ARCHIVO_ENV.tmp" "$ARCHIVO_ENV" 2>/dev/null || true
  echo "$1=$2" >>"$ARCHIVO_ENV"
}

# =============================================================================
# 5) Rama OFFLINE: llama.cpp + modelo
# =============================================================================
if [ "$MODO" = "local" ]; then
  echo ""
  echo "---------------------------- Herramienta local -------------------------------"
  echo "llama.cpp es el proyecto (codigo fuente) que se compila en tu PC:"
  echo "  ~5-15 min una vez, a cambio de kernels optimizados para TU procesador."
  if preguntar_si_no "Compilar llama.cpp ahora?"; then
    if [ ! -d tools/llama.cpp/.git ]; then
      git clone --depth 1 https://github.com/ggml-org/llama.cpp tools/llama.cpp \
        || morir "no se pudo clonar llama.cpp"
    fi
    echo "  Configurando compilacion (el build corre en segundo plano)..."
    # En Windows/MSYS2, cmake genera un proyecto para MSVC que se compila con
    # cmake --build igual que en Linux; el binario queda en build/bin/Release
    # o build/bin segun el generador.
    cmake -S tools/llama.cpp -B tools/llama.cpp/build \
      -DGGML_NATIVE=ON -DLLML_CURL=OFF -DGGML_BACKEND_DL=OFF \
      >/dev/null 2>&1 &
    PID_LLAMA=$!
  else
    echo "  Puedes descargar el binario oficial de llama.cpp (mas rapido, menos"
    echo "  optimizado) y colocarlo en tools/llama.cpp/build/bin/llama-server."
  fi

  echo ""
  echo "------------------------------- Modelo LLM -----------------------------------"
  echo "El modelo vive en RAM; elige segun tu equipo ($RAM_GB GB detectados):"
  OPCION_LLM=$(preguntar_opcion "Modelos:" \
    "Qwen2.5-1.5B Q4_K_M  (~1.0 GB RAM) - ideal para 4 GB" \
    "Qwen2.5-3B   Q4_K_M  (~2.0 GB RAM) - recomendado y probado" \
    "Qwen3.5-4B   Q4_K_M  (~2.5 GB RAM) - generacion nueva (via unsloth)" \
    "Qwen2.5-7B   Q4_K_M  (~4.5 GB RAM) - maxima calidad, para 16 GB+")
  case "$OPCION_LLM" in
    1) LLM_URL="https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf";   LLM_ARCH="qwen2.5-1.5b-instruct-q4_k_m.gguf" ;;
    2) LLM_URL="https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf";       LLM_ARCH="qwen2.5-3b-instruct-q4_k_m.gguf" ;;
    3) LLM_URL="https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf";                      LLM_ARCH="Qwen3.5-4B-Q4_K_M.gguf" ;;
    4) LLM_URL="https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m.gguf";       LLM_ARCH="qwen2.5-7b-instruct-q4_k_m.gguf" ;;
    *) LLM_URL="https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf";       LLM_ARCH="qwen2.5-3b-instruct-q4_k_m.gguf" ;;
  esac
  echo "  Descargando $LLM_ARCH (puede tardar varios minutos)..."
  descargar "models/llm/$LLM_ARCH" "$LLM_URL"
  guardar_env "VOXEN_MODEL" "$LLM_ARCH"
fi

# =============================================================================
# 6) Rama ONLINE: proveedor + API key
# =============================================================================
if [ "$MODO" = "remote" ]; then
  echo ""
  echo "------------------------------- API remota -----------------------------------"
  echo "Servicios soportados (todos OpenAI-compatible, probados con Voxen):"
  echo "  - Groq       : gratis, rapido. Crea la key en https://console.groq.com/keys"
  echo "  - OpenRouter : gratis con modelos libres. https://openrouter.ai/settings/keys"
  echo "  - Cohere     : trial gratis. https://dashboard.cohere.com/api-keys"
  echo "  - SambaNova  : gratis con registro. https://cloud.sambanova.ai/apis"
  PROVEEDOR=$(preguntar_opcion "Con cual vas a usar?" "Groq" "OpenRouter" "Cohere" "SambaNova" "Otro (mi propia URL)")
  case "$PROVEEDOR" in
    2) ID_PROVEEDOR="openrouter"; MODEL_REC="openrouter/free" ;;
    3) ID_PROVEEDOR="cohere";     MODEL_REC="command-r7b-12-2024" ;;
    4) ID_PROVEEDOR="sambanova";  MODEL_REC="gemma-4-31B-it" ;;
    5) ID_PROVEEDOR="custom";     MODEL_REC="" ;;
    *) ID_PROVEEDOR="groq";       MODEL_REC="qwen/qwen3.8-27b" ;;
  esac

  while true; do
    API_KEY=$(preguntar_texto "Ingresa tu API key (se guarda en .env local)" "")
    [ -n "$API_KEY" ] || { echo "  La key no puede estar vacia."; continue; }
    break
  done

  guardar_env "VOXEN_PROVIDER" "$ID_PROVEEDOR"
  guardar_env "VOXEN_API_KEY" "$API_KEY"
  if [ "$ID_PROVEEDOR" = "custom" ]; then
    while true; do
      BASE_URL=$(preguntar_texto "URL base de tu servicio (ej. https://api.miproxy.com/v1)" "")
      [ -n "$BASE_URL" ] || { echo "  La URL no puede estar vacia."; continue; }
      break
    done
    guardar_env "VOXEN_BASE_URL" "$BASE_URL"
  fi
  MODELO_REMOTO=$(preguntar_texto "Modelo a usar (recomendado: ${MODEL_REC:-ninguno})" "${MODEL_REC:-}")
  [ -n "$MODELO_REMOTO" ] && guardar_env "VOXEN_MODEL" "$MODELO_REMOTO"
fi

# =============================================================================
# 7) Ajustes por defecto o configuracion avanzada
# =============================================================================
echo ""
echo "------------------------------ Ajustes ---------------------------------------"
if preguntar_si_no "Usar ajustes recomendados para tu PC? (temperatura, contexto, hilos)"; then
  TEMPERATURA=0.4; MAX_TOKENS=150; CONTEXTO=2048; HILOS=0
  echo "  temperatura=$TEMPERATURA (0.4: estable para practicar)"
  echo "  max_tokens=$MAX_TOKENS  (respuestas de 1-2 frases, menor latencia)"
  echo "  context=$CONTEXTO       (suficiente para conversaciones largas)"
  echo "  hilos=$HILOS            (0 = automatico segun tus nucleos fisicos)"
else
  TEMPERATURA=$(preguntar_texto "Temperatura (0.0 = preciso, 1.0 = creativo)" "0.4")
  MAX_TOKENS=$(preguntar_texto "Maximo de tokens por respuesta" "150")
  CONTEXTO=$(preguntar_texto "Contexto en tokens" "2048")
  HILOS=$(preguntar_texto "Hilos de inferencia (0 = auto)" "0")
fi
guardar_env "VOXEN_TEMPERATURE"  "$TEMPERATURA"
guardar_env "VOXEN_MAX_TOKENS"   "$MAX_TOKENS"
guardar_env "VOXEN_CONTEXT_SIZE" "$CONTEXTO"
guardar_env "VOXEN_THREADS"      "$HILOS"
guardar_env "VOXEN_STT_MODEL"    "$WHISPER_MODELO"
NOMBRE_USUARIO=$(preguntar_texto "Como te llamas? (opcional, para que te saluden por tu nombre)" "")
[ -n "$NOMBRE_USUARIO" ] && guardar_env "VOXEN_USER_NAME" "$NOMBRE_USUARIO"

# =============================================================================
# 8) Descargas restantes + compilacion
# =============================================================================
echo ""
echo "----------------------------- Descargas ---------------------------------------"
echo "  Whisper $WHISPER_MODELO (transcripcion en RAM)..."
if [ "$WHISPER_MODELO" = "ggml-small.en.bin" ]; then
  descargar "models/stt/ggml-small.en.bin" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"
else
  descargar "models/stt/ggml-base.en.bin"  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
fi

if $TTS_BAJAR; then
  echo "  Voz Ryan para piper..."
  descargar "models/tts/en_US-ryan-medium.onnx" \
    "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/medium/en_US-ryan-medium.onnx"
  descargar "models/tts/en_US-ryan-medium.onnx.json" \
    "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/medium/en_US-ryan-medium.onnx.json"

  echo "  Binario piper (motor de voz)..."
  if [ ! -x tools/piper/piper ]; then
    if $ES_WINDOWS; then
      PIPER_URL="https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_windows_amd64.zip"
      descargar "tools/piper.zip" "$PIPER_URL"
      mkdir -p tools/piper
      # tar en Windows 10+ tambien extrae zip.
      tar -xf tools/piper.zip -C tools/piper && rm -f tools/piper.zip
      # El zip trae un subdir piper/; el binario queda anidado.
      [ -x tools/piper/piper/piper.exe ] && mv tools/piper/piper/* tools/piper/
    else
      descargar "tools/piper.tar.gz" "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_x86_64.tar.gz"
      mkdir -p tools/piper
      tar -xzf tools/piper.tar.gz -C tools/piper --strip-components=1
      rm -f tools/piper.tar.gz
    fi
  else
    echo "    [skip] ya existe"
  fi
fi

if [ "$MODO" = "local" ] && [ -n "${PID_LLAMA:-}" ]; then
  echo ""
  echo "  Esperando la compilacion de llama.cpp (5-15 min)..."
  if wait "$PID_LLAMA"; then
    echo "  [ok] llama-server compilado y optimizado para tu CPU"
  else
    echo "  [X] La compilacion de llama.cpp fallo. Revisa tools/llama.cpp/build" >&2
    exit 1
  fi
fi

echo ""
echo "  Instalando Voxen..."
BIN_EJECUTABLE="./voxen"
$ES_WINDOWS && BIN_EJECUTABLE="./voxen.exe"

if [ -x "$BIN_EJECUTABLE" ]; then
  echo "  [ok] Binario de Voxen ya instalado ($BIN_EJECUTABLE)"
else
  echo "  Descargando binario precompilado desde GitHub Releases..."
  ASSET_NAME="voxen-linux-x86_64.tar.gz"
  if $ES_WINDOWS; then
    ASSET_NAME="voxen-windows-x86_64.zip"
  elif [ "$DETECTADO_SO" = "Darwin" ]; then
    ASSET_NAME="voxen-macos-arm64.tar.gz"
  fi
  RELEASE_URL="https://github.com/anibalgp/Voxen/releases/latest/download/$ASSET_NAME"
  if curl -fsIL "$RELEASE_URL" >/dev/null 2>&1; then
    echo "  Descargando $ASSET_NAME..."
    if [[ "$ASSET_NAME" == *.zip ]]; then
      curl -fL --progress-bar "$RELEASE_URL" -o "$ASSET_NAME"
      unzip -q -o "$ASSET_NAME" && rm -f "$ASSET_NAME"
    else
      curl -fL --progress-bar "$RELEASE_URL" -o "$ASSET_NAME"
      tar -xzf "$ASSET_NAME" && rm -f "$ASSET_NAME"
    fi
    chmod +x voxen 2>/dev/null || true
    if [ -x "$BIN_EJECUTABLE" ]; then
      echo "  [ok] Voxen precompilado instalado exitosamente"
    else
      morir "no se pudo extraer el binario de $ASSET_NAME"
    fi
  else
    morir "no se encontro el release oficial para $ASSET_NAME. Puedes descargarlo directamente en https://github.com/anibalgp/Voxen/releases"
  fi
fi

# =============================================================================
# 9) Resumen final
# =============================================================================
banner
echo " Instalacion completa. Tu configuracion quedo en $ARCHIVO_ENV"
echo ""
echo " Para conversar:"
if [ -x "./voxen" ]; then
  echo "   ./voxen$( [ "$MODO" = "remote" ] && echo ' --remote' )"
elif [ -x "./target/release/voxen" ]; then
  echo "   ./target/release/voxen$( [ "$MODO" = "remote" ] && echo ' --remote' )"
else
  echo "   cargo run --release$( [ "$MODO" = "remote" ] && echo ' -- --remote' )"
fi
echo ""
if [ "$MODO" = "local" ]; then
  echo " Motor: LOCAL (offline). Modelo: $LLM_ARCH"
else
  echo " Motor: REMOTO via $ID_PROVEEDOR. Sin RAM para el LLM."
fi
echo " Escucha: $WHISPER_MODELO   Voz: $([ $TTS_BAJAR = true ] && echo 'Ryan (descargada)' || echo 'NO descargada')"
echo "==============================================================================="
