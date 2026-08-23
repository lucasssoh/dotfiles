pub mod network_manager;
pub mod types;

pub use network_manager::NetworkManager;
// Not used yet outside this module -- wired into ui/network_list.rs and
// ui/saved_list.rs in Phase 1b (see the project plan).
#[allow(unused_imports)]
pub use types::{AccessPoint, SavedNetwork, SecurityType};
