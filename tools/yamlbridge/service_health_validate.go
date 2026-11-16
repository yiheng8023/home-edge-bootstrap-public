package main

import "errors"

// Validate the original registration before any shell JSON transformation can
// collapse duplicate keys. This command has no controller or runtime effects.
func runServiceHealthValidate(args []string) error {
	if len(args) != 2 {
		return errors.New("usage: service-health-validate REQUEST NEW_VALIDATED_REQUEST")
	}
	raw, err := shRead(args[0], maxBytes)
	if err != nil {
		return err
	}
	var request serviceHealthRequest
	if err := shDecode(raw, &request); err != nil {
		return err
	}
	if err := request.validate(); err != nil {
		return err
	}
	return shWriteJSON(args[1], request, true)
}
