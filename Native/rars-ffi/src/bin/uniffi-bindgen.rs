//! `cargo run --bin uniffi-bindgen -- generate …`: UniFFI's binding generator. Kept in this
//! crate so its version always matches the `uniffi` the library was built with.

fn main() {
    uniffi::uniffi_bindgen_main()
}
