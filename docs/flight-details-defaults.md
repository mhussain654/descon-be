# Flight details defaults

Staff add a candidate's flight details from the candidate's workflow panel ("Add
flight details"): airline, flight number, sector, departure date and time, and
the ticket file. That moves the candidate to Flight Details Uploaded and saves
the details for that candidate (`candidate_flight_details` and the stage
history), as before.

## Defaults

Admin Settings → **Flight details** holds one default airline, flight number,
sector and departure date and time (`FlightDetailSetting`, `GET/PATCH
/api/v1/admin/flight_detail_setting`, `manage_workflow` -- Admin and MPS). Useful
when a batch of candidates flies together.

- The "Add flight details" dialog opens with the defaults filled in (the allowed
  transition's `flight_details_uploaded` fields carry a `default`; the departure
  as a local date and time such as `2026-11-20T14:30`). Staff can change any of
  them; the ticket is always chosen per candidate.
- What is sent is what is saved. Changing the defaults later only affects
  candidates added afterwards.
- The departure date and time are set or cleared together.
- Every change to the defaults is audited (`flight_detail_setting_updated`).

## Departure time zone

The staff form sends the departure without an offset (`2026-11-20T14:30`), which
is read as Pakistan time (`CandidateWorkflows::FlightDetails::PakistanDepartureTime`):
14:30 is saved as 09:30 UTC and shows as 14:30 on phones in Pakistan. A value with
an offset is kept as that moment. Flights recorded before this fix were saved as if
the typed time were UTC (shown 5 hours late) and are not changed automatically.

## Where the candidate sees it

The mobile Status tab shows "Your flight" (airline, flight number, sector,
departure) in the Ready to Fly step, with Download Ticket once a ticket is
attached. Home shows the same box while Ready to Fly is the current step, and the
medical appointment box while Medical is the current step.
