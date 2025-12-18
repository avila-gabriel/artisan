import { Ok, Error } from "./gleam.mjs";

export async function read_file_as_text(inputId) {
  const input = document.getElementById(inputId);

  if (!input || !input.files || input.files.length === 0) {
    return new Error("Nenhum arquivo selecionado");
  }

  const file = input.files[0];

  // 1. Check extension
  const isCsvExtension = file.name.toLowerCase().endsWith(".csv");

  // 2. Check MIME type (can be empty or unreliable, so we don't trust it alone)
  const isCsvMime =
    file.type === "text/csv" ||
    file.type === "application/vnd.ms-excel";

  if (!isCsvExtension && !isCsvMime) {
    return new Error("O arquivo selecionado não é um CSV");
  }

  try {
    const text = await file.text();
    return new Ok(text);
  } catch (e) {
    return new Error("Erro ao ler o arquivo: " + e.message);
  }
}

