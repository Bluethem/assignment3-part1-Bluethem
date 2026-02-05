#!/bin/sh
#Exercise 1

#Verificar el numero de argumentos en el comando
if [ $# -ne 2 ]; then
       echo "Error: faltan argumentos"
       exit 1
fi


#Verificar si filesdir es un directorio
if [ ! -d "$1" ]; then
	echo "Error: filesdir no es un directorio"
	exit 1
fi

#Numero de archivos
filesdir=$(find "$1" -type f | wc -l)

#Numero de palabras que se repite en el directorio
searchstr=$(grep -r "$2" "$1"| wc -l)

#Devolver el mensaje
echo "The number of files are $filesdir and the number of matching lines are $searchstr"
