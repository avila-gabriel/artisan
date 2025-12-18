import { Ok, Error } from "./gleam.mjs";

export async function read_file_as_text(inputId) {
  const input = document.getElementById(inputId);
  if (!input || !input.files || input.files.length === 0) {
    return new Error("No file selected");
  }

  try {
    const file = input.files[0];
    const text = await file.text();
    return new Ok(text);
  } catch (e) {
    return new Error("Error reading file: " + e.message);
  }
}

