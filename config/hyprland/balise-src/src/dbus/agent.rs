//! BlueZ pairing agent (`org.bluez.Agent1`), Phase 3. Adapted verbatim
//! from orbit-vendor/src/dbus/agent.rs: every method forwards to the GTK
//! side over an `async_channel`, and requests that need an answer (PIN/
//! passkey/confirmation) create a fresh one-shot-sized channel and await
//! the reply from the UI.

use async_channel::Sender;
use zbus::interface;
use zbus::zvariant::ObjectPath;

/// Mirrors Orbit's Bt* AppEvent variants, scoped to just the agent
/// callbacks (Balise's app/mod.rs wraps these in its own AppEvent).
pub enum AgentEvent {
    PinRequest(String, Sender<String>),
    PinDisplay(String, String),
    PasskeyRequest(String, Sender<u32>),
    PasskeyDisplay(String, u32, u16),
    ConfirmRequest(String, u32, Sender<bool>),
    AuthRequest(String, Sender<bool>),
    Cancel,
}

pub struct BluetoothAgent {
    event_tx: Sender<AgentEvent>,
}

impl BluetoothAgent {
    pub fn new(event_tx: Sender<AgentEvent>) -> Self {
        Self { event_tx }
    }
}

#[interface(name = "org.bluez.Agent1")]
impl BluetoothAgent {
    async fn release(&self) {}

    async fn request_pin_code(&self, device: ObjectPath<'_>) -> Result<String, zbus::fdo::Error> {
        let (tx, rx) = async_channel::bounded(1);
        let _ = self.event_tx.send(AgentEvent::PinRequest(device.to_string(), tx)).await;
        rx.recv().await.map_err(|_| zbus::fdo::Error::Failed("Request cancelled".to_string()))
    }

    async fn display_pin_code(&self, device: ObjectPath<'_>, pincode: &str) {
        let _ = self.event_tx.send(AgentEvent::PinDisplay(device.to_string(), pincode.to_string())).await;
    }

    async fn request_passkey(&self, device: ObjectPath<'_>) -> Result<u32, zbus::fdo::Error> {
        let (tx, rx) = async_channel::bounded(1);
        let _ = self.event_tx.send(AgentEvent::PasskeyRequest(device.to_string(), tx)).await;
        rx.recv().await.map_err(|_| zbus::fdo::Error::Failed("Request cancelled".to_string()))
    }

    async fn display_passkey(&self, device: ObjectPath<'_>, passkey: u32, entered: u16) {
        let _ = self.event_tx.send(AgentEvent::PasskeyDisplay(device.to_string(), passkey, entered)).await;
    }

    async fn request_confirmation(&self, device: ObjectPath<'_>, passkey: u32) -> Result<(), zbus::fdo::Error> {
        let (tx, rx) = async_channel::bounded(1);
        let _ = self.event_tx.send(AgentEvent::ConfirmRequest(device.to_string(), passkey, tx)).await;
        if rx.recv().await.unwrap_or(false) {
            Ok(())
        } else {
            Err(zbus::fdo::Error::Failed("User rejected confirmation".to_string()))
        }
    }

    async fn request_authorization(&self, device: ObjectPath<'_>) -> Result<(), zbus::fdo::Error> {
        let (tx, rx) = async_channel::bounded(1);
        let _ = self.event_tx.send(AgentEvent::AuthRequest(device.to_string(), tx)).await;
        if rx.recv().await.unwrap_or(false) {
            Ok(())
        } else {
            Err(zbus::fdo::Error::Failed("User rejected authorization".to_string()))
        }
    }

    async fn authorize_service(&self, _device: ObjectPath<'_>, _uuid: &str) -> Result<(), zbus::fdo::Error> {
        Ok(()) // auto-approved, matching Orbit
    }

    async fn cancel(&self) {
        let _ = self.event_tx.send(AgentEvent::Cancel).await;
    }
}
