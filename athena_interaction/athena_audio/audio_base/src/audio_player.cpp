// Copyright (c) 2021 Beijing Xiaomi Mobile Software Co., Ltd. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <map>
#include <queue>
#include <vector>
#include <memory>
#include <algorithm>

#include "audio_base/audio_player.hpp"

athena_audio::AudioPlayer::AudioPlayer(
  int channel,
  callback finish_callback,
  int volume_group,
  int volume)
{
  if (activeNum_ == 0) {
    init_success_ = Init();
    channelNum_ = Mix_AllocateChannels(DEFAULT_PLAY_CHANNEL_NUM);
    thread_num_ = std::vector<int>(channelNum_, 0);
    volume_ = std::vector<int>(channelNum_, volume);
    volume_group_ = std::vector<int>(channelNum_, INDE_VOLUME_GROUP);
    Mix_ChannelFinished(chuckFinish_callback);
    chucks_ = std::map<int, std::queue<chuck_ptr>>();
    databuff_ = std::map<int, std::queue<Uint8 *>>();
    finish_callbacks_ = std::map<int, callback>();
  }
  if (init_success_ == false) {
    std::cout << "[AudioPlayer]Init_Error, SDL or Mixer init failed.\n";
    self_channel_ = ERROR_CHANNEL;
    init_ready_ = false;
    return;
  }

  self_channel_ = channel;
  if (chucks_.count(self_channel_) == 0) {
    activeNum_++;
    chucks_.insert(
      std::map<int, std::queue<chuck_ptr>>::value_type(
        self_channel_,
        std::queue<chuck_ptr>()));
    databuff_.insert(
      std::map<int, std::queue<Uint8 *>>::value_type(
        self_channel_,
        std::queue<Uint8 *>()));
    finish_callbacks_.insert(
      std::map<int, callback>::value_type(
        self_channel_,
        finish_callback));
    if (self_channel_ >= channelNum_) {
      channelNum_ = Mix_AllocateChannels(self_channel_ + 1);
      for (int ch = thread_num_.size(); ch < channelNum_; ch++) {
        thread_num_.push_back(0);
        volume_.push_back(volume);
        volume_group_.push_back(volume_group);
      }
    }
    init_ready_ = true;
    thread_num_[self_channel_] = 0;
    volume_[self_channel_] = GetGroupVolume(volume_group, volume);
    volume_group_[self_channel_] = volume_group;
    std::cout << "[AudioPlayer]Open on Channel[" << self_channel_ << "].\n";
  } else {
    std::cout << "[AudioPlayer]Init_Error, Channel[" << self_channel_ << "] be used.\n";
    self_channel_ = ERROR_CHANNEL;
    init_ready_ = false;
  }
}

athena_audio::AudioPlayer::~AudioPlayer()
{
  if (init_ready_ == false) {return;}
  thread_num_[self_channel_] = 0;
  activeNum_--;
  while (chucks_[self_channel_].empty() == false) {
    chucks_[self_channel_].pop();
    databuff_[self_channel_].pop();
  }
  chucks_.erase(self_channel_);
  databuff_.erase(self_channel_);
  finish_callbacks_.erase(self_channel_);
  std::cout << "[AudioPlayer]AudioPlayer close on Channel[" << self_channel_ << "]\n";
  if (activeNum_ == 0) {Close();}
}

int athena_audio::AudioPlayer::GetFreeChannel()
{
  int ch = 0;
  while (1) {
    if (chucks_.count(ch) == 0) {return ch;}
    ch++;
  }
  return -1;
}

bool athena_audio::AudioPlayer::InitSuccess()
{
  return init_success_;
}

bool athena_audio::AudioPlayer::OpenReference()
{
  if (init_success_ == false && reference_id_ != 0) {return false;}
  int deviceNum = SDL_GetNumAudioDevices(SDL_TRUE);
  if (deviceNum < 1) {
    std::cout << "[AudioPlayer]Cant open reference channel:1\n";
    return false;
  } else {
    SDL_AudioSpec desired_spec;
    SDL_zero(desired_spec);
    desired_spec.freq = AUDIO_FREQUENCY;
    desired_spec.format = AUDIO_FORMAT;
    desired_spec.channels = AUDIO_CHANNELS;
    desired_spec.samples = AUDIO_CHUCKSIZE;
    desired_spec.callback = audioRecording_callback;
    reference_id_ = SDL_OpenAudioDevice(
      SDL_GetAudioDeviceName(0, SDL_TRUE),
      SDL_TRUE,
      &desired_spec,
      &obtained_spec_,
      SDL_AUDIO_ALLOW_FORMAT_CHANGE);
    if (reference_id_ == 0) {
      std::cout << "[AudioPlayer]Cant open reference channel:2\n";
      return false;
    } else {
      SDL_PauseAudioDevice(reference_id_, SDL_FALSE);
      reference_data_ = std::queue<Uint8>();
      std::cout << "[AudioPlayer]Success open reference channel\n";
      return true;
    }
  }
}

void athena_audio::AudioPlayer::CloseReference()
{
  if (reference_id_ == 0) {return;}
  SDL_PauseAudioDevice(reference_id_, SDL_TRUE);
  SDL_CloseAudioDevice(reference_id_);
  reference_id_ = 0;
  while (reference_data_.empty() == false) {
    reference_data_.pop();
  }
  std::cout << "[AudioPlayer]Close reference channel\n";
}

int athena_audio::AudioPlayer::GetReferenceData(Uint8 * buff, int need_size)
{
  if (reference_id_ != 0) {
    int out_size = std::min(need_size, static_cast<int>(reference_data_.size()));
    for (int a = 0; a < out_size; a++) {
      buff[a] = reference_data_.front();
      reference_data_.pop();
    }
    return out_size;
  }
  return 0;
}

size_t athena_audio::AudioPlayer::GetReferenceDataSize()
{
  return reference_data_.size();
}

void athena_audio::AudioPlayer::SetFinishCallBack(callback finish_callback)
{
  if (init_ready_ == false) {return;}
  finish_callbacks_[self_channel_] = finish_callback;
}

int athena_audio::AudioPlayer::SetVolume(int volume)
{
  if (init_ready_ == false) {return -1;}
  int gp_num = volume_group_[self_channel_];
  if (gp_num == INDE_VOLUME_GROUP) {
    return SetSingleVolume(self_channel_, volume);
  }
  int real_set = -1;
  for (int ch = 0; ch < static_cast<int>(volume_group_.size()); ch++) {
    if (volume_group_[ch] == gp_num) {
      real_set = SetSingleVolume(ch, volume);
    }
  }
  return real_set;
}

void athena_audio::AudioPlayer::SetVolumeGroup(int volume_gp)
{
  if (init_ready_ == false) {return;}
  volume_[self_channel_] = GetGroupVolume(volume_gp, volume_[self_channel_]);
  volume_group_[self_channel_] = volume_gp;
}

int athena_audio::AudioPlayer::GetVolume()
{
  if (init_ready_ == false) {return -1;}
  return volume_[self_channel_];
}

void athena_audio::AudioPlayer::AddPlay(Uint8 * buff, int len)
{
  if (self_channel_ >= 0 && init_ready_ && buff != nullptr && len > 0) {
    auto chuck = std::make_shared<Mix_Chunk>();
    Uint8 * p = new Uint8[len];
    memcpy(p, buff, len);
    databuff_[self_channel_].push(p);
    chuck->abuf = p;
    chuck->alen = len;
    chuck->volume = volume_[self_channel_];
    chucks_[self_channel_].push(chuck);
    if (chucks_[self_channel_].size() == 1) {
      auto play_thread_ = std::thread(PlayThreadFunc, self_channel_, ++thread_num_[self_channel_]);
      play_thread_.detach();
    }
  } else {
    std::cout << "[AudioPlayer][Error]Can't play audio\n";
  }
}

void athena_audio::AudioPlayer::AddPlay(const char * file)
{
  Mix_Chunk * chuck = Mix_LoadWAV(file);
  if (chuck == nullptr || chuck->alen <= 0) {
    std::cout << "[AudioPlayer][Error]Can't load audio from:" << file << std::endl;
    return;
  }
  AddPlay(chuck->abuf, chuck->alen);
  Mix_FreeChunk(chuck);
}

void athena_audio::AudioPlayer::StopPlay()
{
  if (init_ready_ == false) {return;}
  thread_num_[self_channel_]++;
  Mix_HaltChannel(self_channel_);
  while (!PopEmpty(self_channel_)) {}
}

bool athena_audio::AudioPlayer::IsPlaying()
{
  if (init_ready_ == false) {return false;}
  return Mix_Playing(self_channel_);
}

bool athena_audio::AudioPlayer::InitReady()
{
  return init_ready_;
}

bool athena_audio::AudioPlayer::Init()
{
  // Init SDL
  if (SDL_Init(SDL_INIT_AUDIO) == -1) {
    std::cout << "[AudioPlayer]SDL_init: Error," << SDL_GetError() << std::endl;
    return false;
  }
  std::cout << "[AudioPlayer]SDL_init: Success\n";
  // Init Audio
  if (Mix_OpenAudio(AUDIO_FREQUENCY, AUDIO_FORMAT, AUDIO_CHANNELS, AUDIO_CHUCKSIZE) == -1) {
    std::cout << "[AudioPlayer]Mix_OpenAudio: Error," << SDL_GetError() << std::endl;
    return false;
  }
  std::cout << "[AudioPlayer]Mix_OpenAudio: Success\n";
  return true;
}

void athena_audio::AudioPlayer::Close()
{
  init_success_ = false;
  Mix_CloseAudio();
  Mix_Quit();
  SDL_Quit();
  std::cout << "[AudioPlayer][AllExit]SDL and Mixer close\n";
}

int athena_audio::AudioPlayer::SetSingleVolume(int channel, int volume)
{
  if (init_ready_ == false) {return -1;}
  volume = volume < 0 ? 0 : (volume > 128 ? 128 : volume);
  Mix_Volume(channel, volume);
  volume_[channel] = volume;
  return volume;
}

int athena_audio::AudioPlayer::GetGroupVolume(int volume_group, int default_volume)
{
  if (volume_group != INDE_VOLUME_GROUP) {
    for (int ch = 0; ch < static_cast<int>(volume_group_.size()); ch++) {
      if (volume_group_[ch] == volume_group) {
        return volume_[ch];
      }
    }
  }
  return default_volume;
}

bool athena_audio::AudioPlayer::PopEmpty(int channel)
{
  if (!chucks_[channel].empty()) {
    delete[] databuff_[channel].front();
    chucks_[channel].pop();
    databuff_[channel].pop();
  }
  return chucks_[channel].empty();
}

void athena_audio::AudioPlayer::PlayThreadFunc(int channel, int thread_num)
{
  auto p_chucks = *chucks_[channel].front();
  p_chucks.volume = volume_[channel];
  Mix_PlayChannel(channel, &p_chucks, 0);
  while (thread_num_[channel] == thread_num && Mix_Playing(channel)) {
    SDL_Delay(DELAY_CHECK_TIME);
  }
  std::cout << "[AudioPlayer]Channel[" << channel << "] thread exit\n";
}

void athena_audio::AudioPlayer::chuckFinish_callback(int channel)
{
  PopEmpty(channel);
  if (chucks_[channel].size() != 0) {
    Mix_PlayChannel(channel, &(*chucks_[channel].front()), 0);
  } else {
    if (finish_callbacks_[channel] != nullptr) {
      finish_callbacks_[channel]();
    }
  }
}

void athena_audio::AudioPlayer::audioRecording_callback(void *, Uint8 * stream, int len)
{
  for (int a = 0; a < len; a++) {
    reference_data_.push(stream[a]);
  }
}
