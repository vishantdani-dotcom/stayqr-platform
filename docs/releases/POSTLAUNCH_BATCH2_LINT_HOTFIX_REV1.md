# StayQR Batch B lint hotfix REV1

Removes the React purity violation introduced by using Date.now() while constructing
the amenity media key inside Amenities.jsx.

The media key now derives uniqueness from the already-unique uploaded object path.
No database, RLS, auth, media policy, checkout, Super Admin, SMS, production, or
responsive behavior is changed.
