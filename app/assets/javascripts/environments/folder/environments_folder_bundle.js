import Vue from 'vue';
import VueApollo from 'vue-apollo';
import VueRouter from 'vue-router';
import createDefaultClient from '~/lib/graphql';
import Translate from '~/vue_shared/translate';
import { apolloProvider } from '../graphql/client';
import EnvironmentsFolderView from './environments_folder_view.vue';
import EnvironmentsFolderApp from './environments_folder_app.vue';

Vue.use(Translate);
Vue.use(VueApollo);

const legacyApolloProvider = new VueApollo({
  defaultClient: createDefaultClient(),
});

export default () => {
  const el = document.getElementById('environments-folder-list-view');
  const environmentsData = el.dataset;
  if (gon.features.environmentsFolderNewLook) {
    Vue.use(VueRouter);

    const folderName = environmentsData.environmentsDataFolderName;
    const folderPath = environmentsData.environmentsDataEndpoint.replace('.json', '');
    const projectPath = environmentsData.environmentsDataProjectPath;
    const helpPagePath = environmentsData.environmentsDataHelpPagePath;

    const router = new VueRouter({
      mode: 'history',
      base: window.location.pathname,
      routes: [
        {
          path: '/',
          name: 'environments_folder',
          component: EnvironmentsFolderApp,
          props: (route) => ({
            scope: route.query.scope,
            folderName,
            folderPath,
          }),
        },
      ],
      scrollBehavior(to, from, savedPosition) {
        if (savedPosition) {
          return savedPosition;
        }
        return { top: 0 };
      },
    });

    return new Vue({
      el,
      provide: {
        projectPath,
        helpPagePath,
      },
      apolloProvider,
      router,
      render(createElement) {
        return createElement('router-view');
      },
    });
  }

  return new Vue({
    el,
    components: {
      EnvironmentsFolderView,
    },
    apolloProvider: legacyApolloProvider,
    provide: {
      projectPath: el.dataset.projectPath,
    },
    data() {
      return {
        endpoint: environmentsData.environmentsDataEndpoint,
        folderName: environmentsData.environmentsDataFolderName,
        cssContainerClass: environmentsData.cssClass,
      };
    },
    render(createElement) {
      return createElement('environments-folder-view', {
        props: {
          endpoint: this.endpoint,
          folderName: this.folderName,
          cssContainerClass: this.cssContainerClass,
        },
      });
    },
  });
};
