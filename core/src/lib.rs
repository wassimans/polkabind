uniffi::setup_scaffolding!();

#[uniffi::export]
pub fn greet(name: String) -> String {
    format!("Hello, {}!", name)
}

#[uniffi::export]
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

#[derive(uniffi::Object)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}
