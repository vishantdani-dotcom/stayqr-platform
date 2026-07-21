# Day 4 Booking Calendar UI Integration

## Included functionality

- Day, week and month timeline views
- Room-wise inventory grid
- Reservation, room-block and direct-stay events
- Status colour legend
- Hotel, room-type, date, status and block-status filters
- Sticky room and date headers
- Horizontal month scrolling
- Server-side room pagination
- Unallocated reservation queue
- Drag-and-drop assignment and reassignment
- Touch-friendly manual Assign/Reassign workflow
- Server-validated date and room movement
- Rate-change rejection
- Optimistic concurrency protection
- Quick reservation, block and stay details
- Room-block create, edit, release and cancel workflows
- Authoritative reload after every mutation
- Reservation create/edit/cancel/no-show calendar invalidation
- Clear errors with automatic rollback to server state

## Production boundaries

- Dragging preserves stay length.
- Dragging never silently changes room type or rate.
- Rate-changing moves must use Reservation Edit.
- Checked-in room changes remain in the Check-In/Stay workflow.
- Day 4 supports one-room reservation movement; group/multi-room workflows
  remain in the Day 5 integration scope.
