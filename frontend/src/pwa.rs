#[cfg(target_arch = "wasm32")]
async fn call_promise(name: &str, arg: Option<&str>) -> Result<String, String> {
    use wasm_bindgen::{JsCast, JsValue};
    use wasm_bindgen_futures::JsFuture;

    let window = web_sys::window().ok_or("window unavailable")?;
    let bridge = js_sys::Reflect::get(window.as_ref(), &JsValue::from_str("pwa217"))
        .map_err(|_| "PWA bridge unavailable")?;
    let function = js_sys::Reflect::get(&bridge, &JsValue::from_str(name))
        .map_err(|_| "PWA operation unavailable")?
        .dyn_into::<js_sys::Function>()
        .map_err(|_| "PWA operation unavailable")?;
    let result = match arg {
        Some(value) => function.call1(&bridge, &JsValue::from_str(value)),
        None => function.call0(&bridge),
    }
    .map_err(js_error)?;
    let promise = result
        .dyn_into::<js_sys::Promise>()
        .map_err(|_| "invalid PWA response")?;
    let value = JsFuture::from(promise).await.map_err(js_error)?;
    Ok(value.as_string().unwrap_or_default())
}

#[cfg(target_arch = "wasm32")]
fn js_error(value: wasm_bindgen::JsValue) -> String {
    value
        .as_string()
        .unwrap_or_else(|| "browser notification operation failed".into())
}

#[cfg(target_arch = "wasm32")]
pub async fn subscribe(public_key: &str) -> Result<String, String> {
    call_promise("subscribe", Some(public_key)).await
}

#[cfg(target_arch = "wasm32")]
pub async fn unsubscribe() -> Result<String, String> {
    call_promise("unsubscribe", None).await
}

#[cfg(target_arch = "wasm32")]
pub async fn status() -> Result<crate::models::PwaStatus, String> {
    let value = call_promise("status", None).await?;
    serde_json::from_str(&value).map_err(|_| "invalid browser status".to_string())
}

#[cfg(target_arch = "wasm32")]
pub async fn install() -> Result<String, String> {
    call_promise("install", None).await
}

#[cfg(target_arch = "wasm32")]
pub fn timezone() -> String {
    use wasm_bindgen::{JsCast, JsValue};
    let Some(window) = web_sys::window() else {
        return "UTC".into();
    };
    let Ok(bridge) = js_sys::Reflect::get(window.as_ref(), &JsValue::from_str("pwa217")) else {
        return "UTC".into();
    };
    let Ok(function) = js_sys::Reflect::get(&bridge, &JsValue::from_str("timezone")) else {
        return "UTC".into();
    };
    let Ok(function) = function.dyn_into::<js_sys::Function>() else {
        return "UTC".into();
    };
    function
        .call0(&bridge)
        .ok()
        .and_then(|v| v.as_string())
        .unwrap_or_else(|| "UTC".into())
}

#[cfg(target_arch = "wasm32")]
pub fn local_date() -> String {
    use wasm_bindgen::{JsCast, JsValue};
    let Some(window) = web_sys::window() else {
        return chrono::Local::now().format("%Y-%m-%d").to_string();
    };
    let Ok(bridge) = js_sys::Reflect::get(window.as_ref(), &JsValue::from_str("pwa217")) else {
        return chrono::Local::now().format("%Y-%m-%d").to_string();
    };
    let Ok(function) = js_sys::Reflect::get(&bridge, &JsValue::from_str("localDate")) else {
        return chrono::Local::now().format("%Y-%m-%d").to_string();
    };
    let Ok(function) = function.dyn_into::<js_sys::Function>() else {
        return chrono::Local::now().format("%Y-%m-%d").to_string();
    };
    function
        .call0(&bridge)
        .ok()
        .and_then(|v| v.as_string())
        .unwrap_or_else(|| chrono::Local::now().format("%Y-%m-%d").to_string())
}

#[cfg(not(target_arch = "wasm32"))]
pub async fn subscribe(_: &str) -> Result<String, String> {
    Err("push requires a browser".into())
}
#[cfg(not(target_arch = "wasm32"))]
pub async fn unsubscribe() -> Result<String, String> {
    Err("push requires a browser".into())
}
#[cfg(not(target_arch = "wasm32"))]
pub async fn status() -> Result<crate::models::PwaStatus, String> {
    Ok(crate::models::PwaStatus {
        supported: false,
        secure: false,
        permission: "unsupported".into(),
        subscribed: false,
        installable: false,
        standalone: false,
    })
}
#[cfg(not(target_arch = "wasm32"))]
pub async fn install() -> Result<String, String> {
    Err("install requires a browser".into())
}
#[cfg(not(target_arch = "wasm32"))]
pub fn timezone() -> String {
    "UTC".into()
}
#[cfg(not(target_arch = "wasm32"))]
pub fn local_date() -> String {
    chrono::Local::now().format("%Y-%m-%d").to_string()
}
