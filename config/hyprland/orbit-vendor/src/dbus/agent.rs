use zbus::interface;
use zbus::zvariant::ObjectPath;
use async_channel::Sender;
use crate::app::AppEvent;

pub struct BluetoothAgent {
    event_tx: Sender<AppEvent>,
}

impl BluetoothAgent {
    pub fn new(event_tx: Sender<AppEvent>) -> Self {
        Self { event_tx }
    }
}

#[interface(name = "org.bluez.Agent1")]
impl BluetoothAgent {
    async fn release(&self) {
        log::info!("Bluetooth Agent released");
    }

    async fn request_pin_code(&self, device: ObjectPath<'_>) -> Result<String, zbus::fdo::Error> {
        log::info!("RequestPinCode called for device: {}", device);
        let (tx, rx) = async_channel::bounded(1);
        let _ = self.event_tx.send(AppEvent::BtPinRequest(device.to_string(), tx)).await;
        
        rx.recv().await.map_err(|_| zbus::fdo::Error::Failed("Request cancelled".to_string()))
    }

    async fn display_pin_code(&self, device: ObjectPath<'_>, pincode: &str) {
        log::info!("DisplayPinCode called for device: {}, pincode: {}", device, pincode);
        let _ = self.event_tx.send(AppEvent::BtPinDisplay(device.to_string(), pincode.to_string())).await;
    }

    async fn request_passkey(&self, device: ObjectPath<'_>) -> Result<u32, zbus::fdo::Error> {
        log::info!("RequestPasskey called for device: {}", device);
        let (tx, rx) = async_channel::bounded(1);
        let _ = self.event_tx.send(AppEvent::BtPasskeyRequest(device.to_string(), tx)).await;
        
        rx.recv().await.map_err(|_| zbus::fdo::Error::Failed("Request cancelled".to_string()))
    }

    async fn display_passkey(&self, device: ObjectPath<'_>, passkey: u32, entered: u16) {
        log::info!("DisplayPasskey called for device: {}, passkey: {}, entered: {}", device, passkey, entered);
        let _ = self.event_tx.send(AppEvent::BtPasskeyDisplay(device.to_string(), passkey, entered)).await;
    }

    async fn request_confirmation(&self, device: ObjectPath<'_>, passkey: u32) -> Result<(), zbus::fdo::Error> {
        log::info!("RequestConfirmation called for device: {}, passkey: {}", device, passkey);
        let (tx, rx) = async_channel::bounded(1);
        let _ = self.event_tx.send(AppEvent::BtConfirmRequest(device.to_string(), passkey, tx)).await;
        
        if rx.recv().await.unwrap_or(false) {
            Ok(())
        } else {
            Err(zbus::fdo::Error::Failed("User rejected confirmation".to_string()))
        }
    }

    async fn request_authorization(&self, device: ObjectPath<'_>) -> Result<(), zbus::fdo::Error> {
        log::info!("RequestAuthorization called for device: {}", device);
        let (tx, rx) = async_channel::bounded(1);
        let _ = self.event_tx.send(AppEvent::BtAuthRequest(device.to_string(), tx)).await;
        
        if rx.recv().await.unwrap_or(false) {
            Ok(())
        } else {
            Err(zbus::fdo::Error::Failed("User rejected authorization".to_string()))
        }
    }

    async fn authorize_service(&self, device: ObjectPath<'_>, uuid: &str) -> Result<(), zbus::fdo::Error> {
        log::info!("AuthorizeService called for device: {}, uuid: {}", device, uuid);
        Ok(())
    }

    async fn cancel(&self) {
        log::info!("Bluetooth Agent request cancelled");
        let _ = self.event_tx.send(AppEvent::BtAgentCancel).await;
    }
}
