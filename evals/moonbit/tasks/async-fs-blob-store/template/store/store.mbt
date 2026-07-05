///|
/// Persist `data` to the file at `path`, overwriting any existing file.
pub async fn save_blob(path : String, data : Bytes) -> Unit {
  ...
}

///|
/// Load the file at `path` saved by `save_blob` and return its contents.
pub async fn load_blob(path : String) -> Bytes {
  ...
}

///|
/// Return true if a blob exists at `path`.
pub async fn has_blob(path : String) -> Bool {
  ...
}
