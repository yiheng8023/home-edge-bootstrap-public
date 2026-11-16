// yamlbridge provides bounded structured-data and service-health tools for the
// router shell. The legacy executable name remains compatible; source data and
// credentials are never printed.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"

	"go.yaml.in/yaml/v3"
)

const maxBytes = 10 * 1024 * 1024

func normalize(v any, depth int) (any, error) {
	if depth > 64 {
		return nil, errors.New("excessive nesting")
	}
	switch x := v.(type) {
	case map[string]any:
		for k, value := range x {
			n, err := normalize(value, depth+1)
			if err != nil {
				return nil, err
			}
			x[k] = n
		}
		return x, nil
	case map[any]any:
		out := make(map[string]any, len(x))
		for k, value := range x {
			key, ok := k.(string)
			if !ok {
				return nil, errors.New("non-string mapping key")
			}
			n, err := normalize(value, depth+1)
			if err != nil {
				return nil, err
			}
			out[key] = n
		}
		return out, nil
	case []any:
		for i := range x {
			n, err := normalize(x[i], depth+1)
			if err != nil {
				return nil, err
			}
			x[i] = n
		}
		return x, nil
	default:
		return v, nil
	}
}

func convert(mode string, raw []byte) ([]byte, error) {
	if len(raw) > maxBytes {
		return nil, errors.New("oversized input")
	}
	if mode != "decode" && mode != "encode" {
		return nil, errors.New("unknown mode")
	}
	// Both forms are YAML; one decoder preserves integer values and rejects duplicates.
	d := yaml.NewDecoder(bytes.NewReader(raw))
	var v, extra any
	if err := d.Decode(&v); err != nil {
		return nil, errors.New("invalid YAML")
	}
	if err := d.Decode(&extra); err != io.EOF {
		return nil, errors.New("multiple documents")
	}
	n, err := normalize(v, 0)
	if err != nil {
		return nil, err
	}
	if _, ok := n.(map[string]any); !ok {
		return nil, errors.New("root must be a mapping")
	}
	if mode == "decode" {
		return json.Marshal(n)
	}
	return yaml.Marshal(n)
}

func run(args []string) error {
	if len(args) == 1 && (args[0] == "--help" || args[0] == "-h") {
		fmt.Println("yamlbridge decode|encode INPUT NEW_OUTPUT")
		fmt.Println("yamlbridge service-probe REQUEST NEW_REPORT")
		fmt.Println("yamlbridge service-health REQUEST NEW_REPORT")
		fmt.Println("yamlbridge service-health-validate REQUEST NEW_VALIDATED_REQUEST")
		fmt.Println("yamlbridge core-test REQUEST NEW_REPORT")
		fmt.Println("yamlbridge service-bind-check REQUEST NEW_REPORT")
		fmt.Println("yamlbridge service-bind-reload REQUEST NEW_BINDING")
		fmt.Println("yamlbridge service-setup REQUEST NEW_OUTPUT_DIRECTORY")
		return nil
	}
	if len(args) > 0 {
		switch args[0] {
		case "service-health":
			return runServiceHealth(args[1:])
		case "service-health-validate":
			return runServiceHealthValidate(args[1:])
		case "core-test":
			return runCoreTest(args[1:])
		case "service-bind-check":
			return runServiceBindCheck(args[1:])
		case "service-bind-reload":
			return runServiceBindReload(args[1:])
		case "service-setup":
			return runServiceSetup(args[1:])
		case "service-probe":
			return runServiceProbe(args[1:])
		}
	}
	if len(args) != 3 {
		return errors.New("usage: yamlbridge decode|encode INPUT OUTPUT")
	}
	f, err := os.Open(args[1])
	if err != nil {
		return errors.New("cannot read input")
	}
	defer f.Close()
	raw, err := io.ReadAll(io.LimitReader(f, maxBytes+1))
	if err != nil {
		return errors.New("cannot read input")
	}
	out, err := convert(args[0], raw)
	if err != nil {
		return err
	}
	o, err := os.OpenFile(args[2], os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return errors.New("output must be a new private file")
	}
	_, writeErr := o.Write(out)
	closeErr := o.Close()
	if writeErr != nil || closeErr != nil {
		os.Remove(args[2])
		return errors.New("cannot write output")
	}
	return nil
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "yamlbridge:", err)
		os.Exit(1)
	}
}
