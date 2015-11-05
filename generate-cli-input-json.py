#!/usr/bin/env python
import argparse
import logging
import json


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

USE_PREVIOUS_VALUE = 'keep'


if __name__ == "__main__":
    partial_parser = argparse.ArgumentParser(add_help=False)
    partial_parser.add_argument('action', choices=['create', 'update'])
    partial_parser.add_argument('--iam', action='store_true')

    # Parse the defined arguments, leave the rest alone
    args, unknown_args = partial_parser.parse_known_args()

    parameter_parser = argparse.ArgumentParser(add_help=False)
    # Optimistically add every '--flag' as an argument with one mandatory string value
    for arg in unknown_args:
        if arg.startswith('--'):
            parameter_parser.add_argument(arg)
    # __dict__ hack because the default Namespace does not allow iteration
    parameters_dict = parameter_parser.parse_args(unknown_args).__dict__

    output_parameters = []
    for key in parameters_dict:
        value = parameters_dict[key]
        if args.action == 'update' and value == USE_PREVIOUS_VALUE:
            output_parameters.append({"ParameterKey": key,  "UsePreviousValue": True})
        else:
            output_parameters.append({"ParameterKey": key,  "ParameterValue": value})

    output_capabilities = []
    if args.iam:
        output_capabilities.append("CAPABILITY_IAM")

    output = {"Parameters": output_parameters, "Capabilities": output_capabilities}
    print(json.dumps(output, indent=4, sort_keys=True))
