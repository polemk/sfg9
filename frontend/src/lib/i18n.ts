import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'

import ptBRRef from '../locales/pt-br/translation.json'

i18n
  .use(initReactI18next)
  .init({
    lng: 'pt-BR',
    fallbackLng: 'pt-BR',
    debug: import.meta.env.DEV,

    interpolation: {
      escapeValue: false, // not needed for react as it escapes by default
    },

    resources: {
      'pt-BR': {
        translation: ptBRRef
      }
    }
  })

export default i18n
