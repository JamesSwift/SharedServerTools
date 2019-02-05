#!/bin/bash
read -p "Do thing? [Y/n]" -n 1 -r
if ! [[ $REPLY =~ ^[Nn]$ ]]
then
	echo Yes
else
	echo No
fi

read -p "Do thing? [y/N]" -n 1 -r
if ! [[ $REPLY =~ ^[yY]$ ]]
then
	echo No
else
	echo Yes
fi