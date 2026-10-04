use serde::Serialize;
use std::{env, process};

#[derive(Debug, PartialEq, Serialize)]
enum Status {
    Active,
    Used,
}
#[derive(Debug, Serialize)]
struct Ticket {
    owner: String,
    status: Status,
}
#[derive(Debug, PartialEq)]
enum BookingError {
    SoldOut,
    Duplicate,
    NotFound,
    AlreadyUsed,
}
#[derive(Debug, Serialize)]
struct Event {
    title: String,
    capacity: usize,
    tickets: Vec<Ticket>,
}
impl Event {
    fn new(title: &str, capacity: usize) -> Self {
        Self {
            title: title.to_owned(),
            capacity,
            tickets: Vec::new(),
        }
    }
    fn register(&mut self, owner: &str) -> Result<&Ticket, BookingError> {
        if self.tickets.iter().any(|t| t.owner == owner) {
            return Err(BookingError::Duplicate);
        }
        if self.tickets.len() >= self.capacity {
            return Err(BookingError::SoldOut);
        }
        self.tickets.push(Ticket {
            owner: owner.to_owned(),
            status: Status::Active,
        });
        Ok(self.tickets.last().expect("ticket was inserted"))
    }
    fn check_in(&mut self, owner: &str) -> Result<(), BookingError> {
        let ticket = self
            .tickets
            .iter_mut()
            .find(|t| t.owner == owner)
            .ok_or(BookingError::NotFound)?;
        if ticket.status == Status::Used {
            return Err(BookingError::AlreadyUsed);
        }
        ticket.status = Status::Used;
        Ok(())
    }
}
fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.first().map(String::as_str) != Some("demo") {
        eprintln!("Usage: evently-cli demo [capacity 1..5000]");
        process::exit(2);
    }
    let capacity = match args.get(1).map(|s| s.parse::<usize>()).unwrap_or(Ok(2)) {
        Ok(n) if (1..=5000).contains(&n) => n,
        _ => {
            eprintln!("Capacity must be 1..5000");
            process::exit(2);
        }
    };
    let mut event = Event::new("Evently Rust lab", capacity);
    event.register("guest-alice").expect("first guest fits");
    event
        .check_in("guest-alice")
        .expect("first check-in succeeds");
    let duplicate = event
        .check_in("guest-alice")
        .expect_err("second check-in fails");
    println!("{}", serde_json::to_string_pretty(&event).unwrap());
    println!("Repeated check-in: {duplicate:?}");
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn capacity_is_enforced() {
        let mut e = Event::new("Test", 1);
        e.register("a").unwrap();
        assert_eq!(e.register("b").unwrap_err(), BookingError::SoldOut);
    }
    #[test]
    fn duplicate_does_not_consume_seat() {
        let mut e = Event::new("Test", 2);
        e.register("a").unwrap();
        assert_eq!(e.register("a").unwrap_err(), BookingError::Duplicate);
        assert_eq!(e.tickets.len(), 1);
    }
    #[test]
    fn check_in_is_single_use() {
        let mut e = Event::new("Test", 1);
        e.register("a").unwrap();
        e.check_in("a").unwrap();
        assert_eq!(e.check_in("a"), Err(BookingError::AlreadyUsed));
    }
    #[test]
    fn unknown_guest_is_rejected() {
        assert_eq!(
            Event::new("Test", 1).check_in("missing"),
            Err(BookingError::NotFound)
        );
    }
}
