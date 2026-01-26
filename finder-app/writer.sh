#!/bin/bash

if [ $# -ne 2 ]; then
       echo "ERROR faltan argumentos"
       exit 1
fi

dir=$(dirname "$1")

mkdir -p "$dir"

if [ $? -ne 0 ]; then
	echo "ERROR: no se pudo crear correctamente el directorio"
	exit 1
fi

echo "$2" > "$1"

if [ $? -ne 0 ]; then
	echo "ERROR: no se pudo crear el archivo"
	exit 1
fi
