from rest_framework import serializers
from .person_names import name_encoding_issue


class NameQualityMixin:
    """Reject damaged new/changed names without preventing ID-based account use."""
    def to_internal_value(self, data):
        if hasattr(data, 'get'):
            errors = {field: ['Name encoding problem. Use an intact official spelling.']
                      for field in ('first_name', 'last_name', 'full_name')
                      if field in self.fields and name_encoding_issue(data.get(field))}
            if errors:
                raise serializers.ValidationError(errors)
        return super().to_internal_value(data)

    def validate_first_name(self, value):
        if name_encoding_issue(value):
            raise serializers.ValidationError('Name encoding problem. Use an intact source or repair the name from its official spelling.')
        return value

    validate_last_name = validate_first_name
    validate_full_name = validate_first_name
