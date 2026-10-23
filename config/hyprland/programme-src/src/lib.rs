//! Programme, the study agenda behind the bar's Programme drawer.
//!
//! The parts without side effects (iCal timetable, the shape of each day,
//! the planner, alerts, quick add, journal) are plain functions with their
//! tests; `daemon` puts them around a socket, an alarm clock and a few
//! child processes, `seance` follows the session under way, and `cli`
//! talks to it.

pub mod ade;
pub mod ajout;
pub mod alertes;
pub mod cli;
pub mod daemon;
pub mod i18n;
pub mod ilot;
pub mod journee;
pub mod khal;
pub mod model;
pub mod plan;
pub mod seance;
pub mod store;
pub mod time;
