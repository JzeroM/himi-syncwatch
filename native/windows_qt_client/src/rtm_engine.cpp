#include "rtm_engine.h"

RtmEngine::RtmEngine(QObject* parent) : QObject(parent), status_("disconnected") {}

void RtmEngine::setStatus(const QString& s) {
    if (status_ == s) {
        return;
    }
    status_ = s;
    emit statusChanged(status_);
}
