import { s__ } from '~/locale';

export const LIST_KEY_CREATED_AT = 'created_at';
export const BASE_SORT_FIELDS = Object.freeze([
  {
    orderBy: 'name',
    label: s__('MlExperimentTracking|Name'),
  },
  {
    orderBy: LIST_KEY_CREATED_AT,
    label: s__('MlExperimentTracking|Created at'),
  },
]);

export const GRAPHQL_PAGE_SIZE = 30;
