#!/usr/bin/sh

rm -rf ../aldaronlau.com/public/*
zola build
cp -r public/* ../aldaronlau.com/public/
