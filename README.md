# TFG 🚀
Automatización de tareas de pentesting basada en contenedores (Kali Linux).

![CI](https://img.shields.io/badge/build-passing-brightgreen)

## 📝 Descripción
este proyecto orquesta herramientas de seguridad para:
- Escanear redes y puertos 
- Detectar y gestionar vulnerabilidades  
- Generar informes

## ✨ Características
- **Automatización completa** mediante Bash/Python + Docker‑Compose    
- **Coste cero**: todo software libre  
- **Portabilidad**: imágenes Docker listadas en `docker/`  


## 📦 Prerequisitos  
- Docker  
- Kali Linux (host o VM)

## 🚀 Instalación rápida
```bash
git clone https://github.com/amazona01/TFG
cd TFG/docker
docker compose up -d
docker compose logs initializer | grep "Admin password:"
```
