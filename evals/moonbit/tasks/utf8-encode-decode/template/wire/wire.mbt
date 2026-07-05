///|
/// Encode a chat message for the wire. The payload is the message text
/// encoded as UTF-8 bytes.
pub fn encode_message(msg : String) -> Bytes {
  ...
}

///|
/// Decode a wire payload produced by `encode_message` back into the
/// original message text.
pub fn decode_message(payload : Bytes) -> String raise {
  ...
}
