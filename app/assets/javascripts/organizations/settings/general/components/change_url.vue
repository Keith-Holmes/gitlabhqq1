<script>
import { GlFormFields, GlButton, GlForm, GlCard } from '@gitlab/ui';
import { s__ } from '~/locale';
import { visitUrlWithAlerts, joinPaths } from '~/lib/utils/url_utility';
import { createAlert } from '~/alert';
import OrganizationUrlField from '~/organizations/shared/components/organization_url_field.vue';
import { FORM_FIELD_PATH, FORM_FIELD_PATH_VALIDATORS } from '~/organizations/shared/constants';
import updateOrganizationMutation from '../graphql/mutations/update_organization.mutation.graphql';

export default {
  name: 'OrganizationSettings',
  components: { OrganizationUrlField, GlFormFields, GlButton, GlForm, GlCard },
  inject: ['organization'],
  i18n: {
    cardHeaderTitle: s__('Organization|Change organization URL'),
    cardHeaderDescription: s__(
      "Organization|Changing an organization's URL can have unintended side effects.",
    ),
    submitButtonText: s__('Organization|Change organization URL'),
    errorMessage: s__(
      'Organization|An error occurred changing your organization URL. Please try again.',
    ),
    successAlertMessage: s__('Organization|Organization URL successfully changed.'),
  },
  formId: 'change-organization-url-form',
  fields: {
    [FORM_FIELD_PATH]: {
      label: s__('Organization|Organization URL'),
      validators: FORM_FIELD_PATH_VALIDATORS,
      groupAttrs: {
        class: 'gl-w-full',
        labelSrOnly: true,
      },
    },
  },
  data() {
    return {
      formValues: {
        path: this.organization.path,
      },
      loading: false,
    };
  },
  computed: {
    isSubmitButtonDisabled() {
      return this.formValues.path === this.organization.path;
    },
  },
  methods: {
    async onSubmit(formValues) {
      this.loading = true;
      try {
        const {
          data: {
            updateOrganization: { errors, organization },
          },
        } = await this.$apollo.mutate({
          mutation: updateOrganizationMutation,
          variables: {
            id: this.organization.id,
            path: formValues.path,
          },
        });

        if (errors.length) {
          // TODO: handle errors when using real API after https://gitlab.com/gitlab-org/gitlab/-/issues/419608 is complete.
          return;
        }

        visitUrlWithAlerts(joinPaths(organization.webUrl, '/settings/general'), [
          {
            id: 'organization-url-successfully-changed',
            message: this.$options.i18n.successAlertMessage,
            variant: 'info',
          },
        ]);
      } catch (error) {
        createAlert({ message: this.$options.i18n.errorMessage, error, captureError: true });
      } finally {
        this.loading = false;
      }
    },
  },
};
</script>

<template>
  <gl-card
    class="gl-new-card"
    header-class="gl-new-card-header gl-flex-direction-column"
    body-class="gl-new-card-body gl-px-5 gl-py-4"
  >
    <template #header>
      <div class="gl-new-card-title-wrapper">
        <h4 class="gl-new-card-title">{{ $options.i18n.cardHeaderTitle }}</h4>
      </div>
      <p class="gl-new-card-description">{{ $options.i18n.cardHeaderDescription }}</p>
    </template>
    <gl-form :id="$options.formId">
      <gl-form-fields
        v-model="formValues"
        :form-id="$options.formId"
        :fields="$options.fields"
        @submit="onSubmit"
      >
        <template #input(path)="{ id, value, validation, input, blur }">
          <organization-url-field
            :id="id"
            :value="value"
            :validation="validation"
            @input="input"
            @blur="blur"
          />
        </template>
      </gl-form-fields>
      <div class="gl-display-flex gl-gap-3">
        <gl-button
          type="submit"
          variant="danger"
          class="js-no-auto-disable"
          :loading="loading"
          :disabled="isSubmitButtonDisabled"
          >{{ $options.i18n.submitButtonText }}</gl-button
        >
      </div>
    </gl-form>
  </gl-card>
</template>
