use gtk4::prelude::*;
use gtk4::{self as gtk, Orientation};
use std::cell::RefCell;
use std::rc::Rc;
use crate::dbus::network_manager::VpnProfile;

struct DnsInfo {
    provider: String,
    is_private: bool,
}

fn identify_dns_provider(dns: &str, ip_prefix: &str) -> DnsInfo {
    let (provider, is_private) = if dns.starts_with("1.1.1.") || dns.starts_with("1.0.0.") || dns.starts_with("2606:4700:") {
        ("Cloudflare", true)
    } else if dns.starts_with("8.8.8.") || dns.starts_with("8.8.4.") || dns.starts_with("2001:4860:") {
        ("Google", false)
    } else if dns.starts_with("9.9.9.") || dns.starts_with("149.112.112.") || dns.starts_with("2620:fe:") || dns.starts_with("2620:f3:") {
        ("Quad9", true)
    } else if dns.starts_with("208.67.") || dns.starts_with("2620:119:") {
        ("OpenDNS", false)
    } else if dns.starts_with("94.140.") || dns.starts_with("2a10:50c0:") {
        ("AdGuard", true)
    } else if !ip_prefix.is_empty() && dns.starts_with(ip_prefix) {
        ("ISP / Router", false)
    } else {
        ("Unknown", false)
    };

    DnsInfo {
        provider: provider.to_string(),
        is_private,
    }
}

#[derive(Clone)]
pub struct VpnList {
    container: gtk::Box,
    list_box: gtk::Box,
    public_ip_label: gtk::Label,
    isp_label: gtk::Label,
    dns_summary_label: gtk::Label,
    dns_expand_icon: gtk::Image,
    dns_details_revealer: gtk::Revealer,
    dns_details_box: gtk::Box,
    profiles: Rc<RefCell<Vec<VpnProfile>>>,
    on_toggle: Rc<RefCell<Option<Rc<dyn Fn(String, bool)>>>>,
}

impl VpnList {
    pub fn new() -> Self {
        let container = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .vexpand(true)
            .hexpand(true)
            .spacing(0)
            .build();

        // Privacy Dashboard Header
        let dashboard = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["orbit-vpn-dashboard"])
            .spacing(6)
            .margin_start(12)
            .margin_end(12)
            .margin_top(4)
            .margin_bottom(4)
            .build();

        let dash_title = gtk::Label::builder()
            .label("PRIVACY DASHBOARD")
            .css_classes(["orbit-section-header"])
            .halign(gtk::Align::Start)
            .build();
        dashboard.append(&dash_title);

        let info_grid = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(6)
            .build();

        // IP & ISP Row
        let ip_row = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(10)
            .build();

        let ip_icon = gtk::Image::builder()
            .icon_name("network-vpn-symbolic")
            .pixel_size(20)
            .css_classes(["orbit-icon-accent"])
            .valign(gtk::Align::Center)
            .build();
        
        let ip_info = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .build();

        let public_ip_label = gtk::Label::builder()
            .label("IP: Detecting...")
            .css_classes(["orbit-ssid"])
            .halign(gtk::Align::Start)
            .selectable(true)
            .build();
        
        let isp_label = gtk::Label::builder()
            .label("Direct Connection")
            .css_classes(["orbit-status"])
            .halign(gtk::Align::Start)
            .build();

        ip_info.append(&public_ip_label);
        ip_info.append(&isp_label);
        
        ip_row.append(&ip_icon);
        ip_row.append(&ip_info);
        info_grid.append(&ip_row);

        // DNS Section — clickable summary + expandable details
        let dns_section = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(2)
            .build();

        let dns_header_row = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(10)
            .css_classes(["orbit-dns-header"])
            .build();

        let dns_icon = gtk::Image::builder()
            .icon_name("web-browser-symbolic")
            .pixel_size(20)
            .css_classes(["orbit-signal-icon"])
            .valign(gtk::Align::Center)
            .build();
        
        let dns_info = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .hexpand(true)
            .build();

        let dns_summary_label = gtk::Label::builder()
            .label("DNS: Detecting...")
            .css_classes(["orbit-status"])
            .halign(gtk::Align::Start)
            .build();

        dns_info.append(&dns_summary_label);

        let dns_expand_icon = gtk::Image::builder()
            .icon_name("pan-end-symbolic")
            .pixel_size(12)
            .css_classes(["orbit-dns-expand-icon"])
            .valign(gtk::Align::Center)
            .build();

        dns_header_row.append(&dns_icon);
        dns_header_row.append(&dns_info);
        dns_header_row.append(&dns_expand_icon);

        // Make the DNS header row clickable
        let dns_details_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(4)
            .margin_start(36)
            .margin_top(4)
            .build();

        let dns_details_revealer = gtk::Revealer::builder()
            .child(&dns_details_box)
            .reveal_child(false)
            .transition_type(gtk::RevealerTransitionType::SlideDown)
            .transition_duration(200)
            .build();

        let click_gesture = gtk::GestureClick::new();
        let revealer_clone = dns_details_revealer.clone();
        let expand_icon_clone = dns_expand_icon.clone();
        click_gesture.connect_released(move |_, _, _, _| {
            let expanded = revealer_clone.reveals_child();
            revealer_clone.set_reveal_child(!expanded);
            if expanded {
                expand_icon_clone.set_icon_name(Some("pan-end-symbolic"));
            } else {
                expand_icon_clone.set_icon_name(Some("pan-down-symbolic"));
            }
        });
        dns_header_row.add_controller(click_gesture);
        dns_header_row.set_cursor_from_name(Some("pointer"));

        dns_section.append(&dns_header_row);
        dns_section.append(&dns_details_revealer);
        info_grid.append(&dns_section);
        
        dashboard.append(&info_grid);

        // VPN Profiles Section
        let scrolled = gtk::ScrolledWindow::builder()
            .vexpand(true)
            .hexpand(true)
            .hscrollbar_policy(gtk::PolicyType::Never)
            .css_classes(["orbit-scrolled"])
            .build();
        
        let scroll_content = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(0)
            .build();
        
        let list_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .css_classes(["orbit-list"])
            .build();
        
        scroll_content.append(&dashboard);
        scroll_content.append(&list_box);
        scrolled.set_child(Some(&scroll_content));
        container.append(&scrolled);
        
        let list = Self {
            container,
            list_box,
            public_ip_label,
            isp_label,
            dns_summary_label,
            dns_expand_icon,
            dns_details_revealer,
            dns_details_box,
            profiles: Rc::new(RefCell::new(Vec::new())),
            on_toggle: Rc::new(RefCell::new(None)),
        };
        
        list.show_placeholder();
        list
    }

    pub fn set_privacy_info(&self, ip: &str, isp: &str, dns_servers: &[String], is_secure: bool) {
        log::info!("VpnList: Updating privacy info: IP={}, ISP={}", ip, isp);
        self.public_ip_label.set_label(&format!("IP: {}", ip));
        self.isp_label.set_label(isp);
        
        let ip_prefix = if ip.contains(':') {
            ip.split(':').take(4).collect::<Vec<_>>().join(":")
        } else {
            ip.split('.').take(3).collect::<Vec<_>>().join(".")
        };

        // Classify each server
        let mut classified: Vec<(String, DnsInfo)> = Vec::new();
        for dns in dns_servers {
            let info = identify_dns_provider(dns, &ip_prefix);
            classified.push((dns.clone(), info));
        }

        // Build summary: deduplicate by provider name, preserving order
        let mut seen_providers: Vec<String> = Vec::new();
        let mut any_private = false;
        for (_, info) in &classified {
            if !seen_providers.contains(&info.provider) {
                seen_providers.push(info.provider.clone());
            }
            if info.is_private {
                any_private = true;
            }
        }

        let summary = if seen_providers.is_empty() {
            "System Default".to_string()
        } else if seen_providers.len() == 1 {
            let name = &seen_providers[0];
            if any_private {
                format!("{} (Private)", name)
            } else {
                name.clone()
            }
        } else {
            let names = seen_providers.join(" + ");
            format!("Mixed ({})", names)
        };

        self.dns_summary_label.set_label(&format!("DNS: {}", summary));

        if any_private {
            self.dns_summary_label.add_css_class("orbit-status-accent");
        } else {
            self.dns_summary_label.remove_css_class("orbit-status-accent");
        }

        // Populate expandable details
        while let Some(child) = self.dns_details_box.first_child() {
            self.dns_details_box.remove(&child);
        }

        for (dns_addr, info) in &classified {
            let row = gtk::Box::builder()
                .orientation(Orientation::Horizontal)
                .spacing(8)
                .build();

            let addr_label = gtk::Label::builder()
                .label(dns_addr)
                .css_classes(["orbit-dns-detail"])
                .halign(gtk::Align::Start)
                .hexpand(true)
                .selectable(true)
                .build();

            let provider_label = gtk::Label::builder()
                .label(&info.provider)
                .css_classes(if info.is_private {
                    vec!["orbit-dns-detail", "orbit-status-accent"]
                } else {
                    vec!["orbit-dns-detail"]
                })
                .halign(gtk::Align::End)
                .build();

            row.append(&addr_label);
            row.append(&provider_label);
            self.dns_details_box.append(&row);
        }

        // Reset expand state when data refreshes
        self.dns_details_revealer.set_reveal_child(false);
        self.dns_expand_icon.set_icon_name(Some("pan-end-symbolic"));

        if is_secure {
            self.isp_label.add_css_class("orbit-status-accent");
            self.isp_label.set_label(&format!("{} (Secure)", isp));
        } else {
            self.isp_label.remove_css_class("orbit-status-accent");
        }
    }
    
    fn show_placeholder(&self) {
        while let Some(child) = self.list_box.first_child() {
            self.list_box.remove(&child);
        }
        let placeholder = gtk::Label::builder()
            .label("No VPN profiles configured")
            .css_classes(["orbit-placeholder"])
            .margin_top(20)
            .build();
        self.list_box.append(&placeholder);
    }
    
    pub fn set_profiles(&self, profiles: Vec<VpnProfile>) {
        log::info!("VpnList: Received {} profiles", profiles.len());
        *self.profiles.borrow_mut() = profiles.clone();
        
        while let Some(child) = self.list_box.first_child() {
            self.list_box.remove(&child);
        }
        
        if profiles.is_empty() {
            self.show_placeholder();
            return;
        }

        let section_header = gtk::Label::builder()
            .label("VPN CONNECTIONS")
            .css_classes(["orbit-section-header"])
            .halign(gtk::Align::Start)
            .build();
        self.list_box.append(&section_header);

        for profile in profiles {
            let row = self.create_vpn_row(&profile);
            self.list_box.append(&row);
        }
    }
    
    fn create_vpn_row(&self, profile: &VpnProfile) -> gtk::Box {
        let row = gtk::Box::builder()
            .orientation(Orientation::Horizontal)
            .spacing(12)
            .css_classes(["orbit-network-row"])
            .build();
        
        let icon_name = if profile.path == "external:riseup" {
            "network-vpn-symbolic"
        } else if profile.path == "external:tailscale" {
            "network-wireless-encrypted-symbolic"
        } else {
            "network-vpn-symbolic"
        };

        let icon = gtk::Image::builder()
            .icon_name(icon_name)
            .pixel_size(20)
            .css_classes(if profile.is_active { vec!["orbit-icon-accent"] } else { vec!["orbit-signal-icon"] })
            .valign(gtk::Align::Center)
            .build();
        row.append(&icon);
        
        let info_box = gtk::Box::builder()
            .orientation(Orientation::Vertical)
            .spacing(2)
            .hexpand(true)
            .valign(gtk::Align::Center)
            .build();
        
        let name_label = if profile.is_external {
            format!("{} (App)", profile.name)
        } else {
            profile.name.clone()
        };

        let name = gtk::Label::builder()
            .label(&name_label)
            .css_classes(["orbit-ssid"])
            .halign(gtk::Align::Start)
            .build();
        info_box.append(&name);
        
        let status_text = if profile.is_active { "Connected" } else { &profile.vpn_type };
        let status = gtk::Label::builder()
            .label(status_text)
            .css_classes(["orbit-status"])
            .halign(gtk::Align::Start)
            .build();
        info_box.append(&status);
        
        row.append(&info_box);
        
        let toggle = gtk::Switch::builder()
            .active(profile.is_active)
            .css_classes(["orbit-toggle-switch"])
            .valign(gtk::Align::Center)
            .tooltip_text("Toggle VPN Connection")
            .build();
        
        let path = profile.path.clone();
        let on_toggle = self.on_toggle.clone();
        toggle.connect_state_set(move |_, state| {
            if let Some(cb) = on_toggle.borrow().as_ref() {
                cb(path.clone(), state);
            }
            gtk::glib::Propagation::Proceed
        });
        
        row.append(&toggle);
        row
    }
    
    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    pub fn set_on_toggle<F: Fn(String, bool) + 'static>(&self, callback: F) {
        *self.on_toggle.borrow_mut() = Some(Rc::new(callback));
    }
}
