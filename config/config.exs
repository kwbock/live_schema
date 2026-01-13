# This file is responsible for configuring your application
# and its dependencies.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

import Config

# Import environment specific config
import_config "#{config_env()}.exs"
