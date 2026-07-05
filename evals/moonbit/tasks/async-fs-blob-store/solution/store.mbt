///|
/// Persist `data` to the file at `path`, overwriting any existing file.
pub async fn save_blob(path : String, data : Bytes) -> Unit {
  @fs.write_file(path, data, create_mode=CreateOrTruncate)
}

///|
/// Load the file at `path` saved by `save_blob` and return its contents.
pub async fn load_blob(path : String) -> Bytes {
  @fs.read_file(path).binary()
}

///|
/// Return true if a blob exists at `path`.
pub async fn has_blob(path : String) -> Bool {
  @fs.exists(path)
}
