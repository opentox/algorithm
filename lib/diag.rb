# Print a diagnostic message
def uri_list 
  puts "My load path is:\n#{$LOAD_PATH.join("\n")} \nI have loaded #{$LOADED_FEATURES.size} objects.\n\n"
end
