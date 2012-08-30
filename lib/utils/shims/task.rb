# Shims for translation to the new architecture (TM).
# Author: Andreas Maunz, 2012

module OpenTox

  # Shims for the Task class
  class Task

    # Check status of a task
    # @return [String] Status
    def status
      self[RDF::OT.hasStatus]
    end

  end

end
