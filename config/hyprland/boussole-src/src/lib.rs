//! Boussole, the study planner behind the bar's Boussole drawer.
//!
//! The parts without side effects (catalogue, iCal timetable, the shape of
//! each day, the planner, alerts, quick add, journal) are plain functions
//! with their tests; `daemon` puts them around a socket, an alarm clock and
//! a few child processes, and `cli` talks to it.

pub mod ade;
pub mod ajout;
pub mod alertes;
pub mod catalogue;
pub mod cli;
pub mod daemon;
pub mod focus;
pub mod i18n;
pub mod ilot;
pub mod journee;
pub mod khal;
pub mod liseuse;
pub mod model;
pub mod plan;
pub mod seance;
pub mod store;
pub mod suivi;
pub mod time;
