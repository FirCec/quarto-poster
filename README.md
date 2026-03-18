# quarto-poster

This repository contains the current implementation of a custom **Quarto extension for academic posters**, developed with a **web-first approach**.

The goal of this project is to create posters that are:
- responsive and readable on screen
- structured and visually clear
- still suitable for print / PDF export

---

## Repository

GitHub: https://github.com/FirCec/quarto-poster/tree/main/poster

---

## Current Status

This is a **work-in-progress implementation**.

The repository includes:
- the Quarto extension source (`_extensions/`)
- a working example document for testing
- project configuration files

The current version allows rendering and evaluation of:
- layout and structure
- spacing and typography
- responsive behavior
- print/PDF output

---

## Requirements

Make sure the following is installed:

- [Quarto](https://quarto.org/)

Check your installation with:

quarto check
---
## How to test?

### 1. clone repo

git clone https://github.com/FirCec/quarto-poster.git

cd quarto-poster/poster

### 2. render the example


quarto render example.qmd

and open the generated html file (example.html) manually in browser when not automatically opened.

### 4. or render full project


quarto render (full project)

## print/PDF testing

To test print behavior:

1. Open the rendered HTML file
2. Use the browser print function (Ctrl + P)
3. Export as PDF
