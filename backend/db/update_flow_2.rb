flow = ChatFlow.find_by(name: 'Audio Visualizer Experiment')
if flow
  flow.update!(
    definition: {
      'nodes' => [
        {
          'id' => 'trigger-start',
          'type' => 'trigger',
          'position' => { 'x' => 100, 'y' => 100 },
          'data' => {
          }
        },
        {
          'id' => 'ask_music',
          'type' => 'question',
          'position' => { 'x' => 100, 'y' => 200 },
          'data' => {
            'content' => 'Quer testar o nosso novo Visualizador de Áudio com tema azul neon e mergulhar em uma experiência interativa?',
            'options' => [
              { 'id' => 'yes_option', 'label' => 'Sim, rock it', 'target' => 'play_music_node' },
              { 'id' => 'no_option', 'label' => 'Agora não', 'target' => 'end_no_music' }
            ]
          }
        },
        {
          'id' => 'play_music_node',
          'type' => 'redirect',
          'position' => { 'x' => 400, 'y' => 200 },
          'data' => {
            'action' => 'play_audio',
            'songName' => 'Música',
            'url' => '/audio/neon-beats.mp3'
          }
        },
        {
          'id' => 'music_started_msg',
          'type' => 'message',
          'position' => { 'x' => 600, 'y' => 200 },
          'data' => {
            'content' => 'A música começou! ✨ Aumente o volume, as estrelas e a onda de neon estão pulsando!'
          }
        },
        {
          'id' => 'end_no_music',
          'type' => 'message',
          'position' => { 'x' => 400, 'y' => 300 },
          'data' => {
            'content' => 'Tudo bem, você pode acessar depois. Aproveite o site!'
          }
        }
      ],
      'edges' => [
        { 'id' => 'e0', 'source' => 'trigger-start', 'target' => 'ask_music' },
        { 'id' => 'e1', 'source' => 'ask_music', 'target' => 'play_music_node', 'sourceHandle' => 'yes_option' },
        { 'id' => 'e2', 'source' => 'ask_music', 'target' => 'end_no_music', 'sourceHandle' => 'no_option' },
        { 'id' => 'e3', 'source' => 'play_music_node', 'target' => 'music_started_msg' }
      ]
    }
  )
  puts "Flow updated with question node successfully."
end
