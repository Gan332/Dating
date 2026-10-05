//! Small, dependency-free Gregorian date core called from Flutter through C ABI.

const INVALID_DATE: i64 = i64::MIN;

fn is_leap_year(year: i32) -> bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

fn days_in_month(year: i32, month: u32) -> Option<u32> {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => Some(31),
        4 | 6 | 9 | 11 => Some(30),
        2 => Some(if is_leap_year(year) { 29 } else { 28 }),
        _ => None,
    }
}

fn days_from_civil(year: i32, month: u32, day: u32) -> Option<i64> {
    let max_day = days_in_month(year, month)?;
    if day == 0 || day > max_day {
        return None;
    }

    let adjusted_year = year - if month <= 2 { 1 } else { 0 };
    let era = adjusted_year.div_euclid(400);
    let year_of_era = adjusted_year - era * 400;
    let shifted_month = month as i32 + if month > 2 { -3 } else { 9 };
    let day_of_year = (153 * shifted_month + 2) / 5 + day as i32 - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;

    Some(i64::from(era) * 146_097 + i64::from(day_of_era) - 719_468)
}

/// Returns the signed number of local calendar days between two Gregorian dates.
/// Invalid dates return i64::MIN so the FFI caller can detect them.
#[no_mangle]
pub extern "C" fn daymark_days_between(
    from_year: i32,
    from_month: i32,
    from_day: i32,
    to_year: i32,
    to_month: i32,
    to_day: i32,
) -> i64 {
    if from_month < 1 || to_month < 1 || from_day < 1 || to_day < 1 {
        return INVALID_DATE;
    }

    let Some(from) = days_from_civil(from_year, from_month as u32, from_day as u32) else {
        return INVALID_DATE;
    };
    let Some(to) = days_from_civil(to_year, to_month as u32, to_day as u32) else {
        return INVALID_DATE;
    };
    to - from
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handles_leap_day_and_year_boundary() {
        assert_eq!(daymark_days_between(2024, 2, 28, 2024, 3, 1), 2);
        assert_eq!(daymark_days_between(2025, 12, 31, 2026, 1, 1), 1);
    }

    #[test]
    fn preserves_signed_elapsed_days() {
        assert_eq!(daymark_days_between(2026, 10, 5, 2026, 10, 1), -4);
        assert_eq!(daymark_days_between(2026, 10, 5, 2026, 10, 5), 0);
    }

    #[test]
    fn rejects_invalid_dates() {
        assert_eq!(daymark_days_between(2025, 2, 29, 2025, 3, 1), INVALID_DATE);
        assert_eq!(daymark_days_between(2026, 13, 1, 2026, 1, 1), INVALID_DATE);
    }
}
