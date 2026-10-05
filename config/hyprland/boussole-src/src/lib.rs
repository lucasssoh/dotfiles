//! Boussole, the study planner behind the bar's Boussole drawer.
//!
//! This crate holds the parts without side effects: the course catalogue,
//! the iCal timetable, the shape of each day and the planner itself. The
//! service around them (socket, alarm clock, khal, notifications) builds on
//! these and keeps the planner a pure function.

pub mod ade;
pub mod catalogue;
pub mod i18n;
pub mod journee;
pub mod model;
pub mod plan;
pub mod time;
